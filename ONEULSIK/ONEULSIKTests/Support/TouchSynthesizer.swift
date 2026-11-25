import Foundation
import UIKit

/// 테스트 호스트 앱 창에 실제 손가락 탭(UITouch + IOHIDEvent)을 보낸다. SwiftUI 버튼의 누르는 영역을 확인하려고 쓴다.
/// UIKit·IOKit의 비공개 API(KIF 방식)를 쓰므로 테스트 전용이다. 시뮬레이터에서만 확인했고 OS가 바뀌면 깨질 수 있다.
@MainActor
enum TouchSynthesizer {
    enum Failure: Error { case unavailable(String) }

    /// 창 좌표 point를 한 번 탭한다(누름 → 0.06초 → 뗌). 화면 전체를 덮는 창이라 창 좌표 = 화면 좌표.
    /// IOHIDEvent를 앱 이벤트 대기열(_enqueueHIDEvent:)에 넣어 UIKit이 실제 손가락처럼 UITouch를 만들고 SwiftUI 제스처까지 전달한다.
    static func tap(_ point: CGPoint, in window: UIWindow) async throws {
        let screenPoint = window.convert(point, to: nil)
        let contextID = try contextID(of: window)
        try enqueue(try makeHIDEvent(point: screenPoint, touching: true), contextID: contextID)
        try await Task.sleep(for: .milliseconds(60))
        try enqueue(try makeHIDEvent(point: screenPoint, touching: false), contextID: contextID)
    }

    /// 창 좌표 from에서 눌러 to까지 손가락을 끌고 뗀다(steps번 나눠 이동, 전체 duration초). 가장자리 스와이프 테스트에 쓴다.
    static func drag(from: CGPoint, to: CGPoint, in window: UIWindow, duration: Double = 0.3, steps: Int = 12) async throws {
        let start = window.convert(from, to: nil)
        let end = window.convert(to, to: nil)
        let contextID = try contextID(of: window)
        let interval = max(0.005, duration / Double(max(steps, 1)))
        try enqueue(try makeHIDEvent(point: start, touching: true), contextID: contextID)
        for step in 1...max(steps, 1) {
            try await Task.sleep(for: .seconds(interval))
            let t = CGFloat(step) / CGFloat(max(steps, 1))
            let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            try enqueue(try makeHIDEvent(point: point, touching: true, moving: true), contextID: contextID)
        }
        try await Task.sleep(for: .milliseconds(20))
        try enqueue(try makeHIDEvent(point: end, touching: false), contextID: contextID)
    }

    /// 끄는 중간에 멈춰 화면을 찍을 수 있게, 누름·이동·뗌을 나눠 보낸다.
    static func beginDrag(at point: CGPoint, in window: UIWindow) throws {
        try enqueue(try makeHIDEvent(point: window.convert(point, to: nil), touching: true), contextID: try contextID(of: window))
    }

    static func moveDrag(from: CGPoint, to: CGPoint, in window: UIWindow, duration: Double = 0.3, steps: Int = 12) async throws {
        let start = window.convert(from, to: nil)
        let end = window.convert(to, to: nil)
        let contextID = try contextID(of: window)
        let interval = max(0.005, duration / Double(max(steps, 1)))
        for step in 1...max(steps, 1) {
            try await Task.sleep(for: .seconds(interval))
            let t = CGFloat(step) / CGFloat(max(steps, 1))
            let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            try enqueue(try makeHIDEvent(point: point, touching: true, moving: true), contextID: contextID)
        }
    }

    static func endDrag(at point: CGPoint, in window: UIWindow) throws {
        try enqueue(try makeHIDEvent(point: window.convert(point, to: nil), touching: false), contextID: try contextID(of: window))
    }

    /// 창의 렌더 컨텍스트 ID. 이벤트에 붙여야 UIKit이 이 창으로 보낸다.
    private static func contextID(of window: UIWindow) throws -> UInt32 {
        guard let value = window.value(forKey: "_contextId") as? NSNumber else { throw Failure.unavailable("_contextId") }
        return value.uint32Value
    }

    private typealias SetDigitizerInfo = @convention(c) (UnsafeMutableRawPointer, UInt32, UInt8, UInt8, CFString?, Double, Float) -> Void
    private static let backBoard = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_NOW)

    private static func enqueue(_ event: UnsafeMutableRawPointer, contextID: UInt32) throws {
        guard let backBoard, let pointer = dlsym(backBoard, "BKSHIDEventSetDigitizerInfo") else {
            throw Failure.unavailable("BKSHIDEventSetDigitizerInfo")
        }
        unsafeBitCast(pointer, to: SetDigitizerInfo.self)(event, contextID, 0, 0, nil, 0, 0)
        try callPointer(UIApplication.shared, "_enqueueHIDEvent:", event)
    }

    // MARK: - IOHIDEvent

    private typealias CreateDigitizer = @convention(c) (CFAllocator?, UInt64, UInt32, UInt32, UInt32, UInt32, UInt32,
                                                       Double, Double, Double, Double, Double, Bool, Bool, UInt32) -> UnsafeMutableRawPointer?
    private typealias CreateFinger = @convention(c) (CFAllocator?, UInt64, UInt32, UInt32, UInt32, Double, Double, Double, Double, Double,
                                                    Double, Double, Double, Double, Double, Bool, Bool, UInt32) -> UnsafeMutableRawPointer?
    private typealias AppendEvent = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, UInt32) -> Void
    private typealias SetInteger = @convention(c) (UnsafeMutableRawPointer, UInt32, Int, UInt32) -> Void
    private typealias SetSenderID = @convention(c) (UnsafeMutableRawPointer, UInt64) -> Void

    private static let ioKit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)

    private static func symbol<T>(_ name: String, as type: T.Type) throws -> T {
        guard let ioKit, let pointer = dlsym(ioKit, name) else { throw Failure.unavailable(name) }
        return unsafeBitCast(pointer, to: type)
    }

    /// 손(hand) 이벤트 안에 손가락 하나를 담는다. 화면 내장 디스플레이 표시(DisplayIntegrated)를 켜야 UIKit이 터치로 받는다.
    private static func makeHIDEvent(point: CGPoint, touching: Bool, moving: Bool = false) throws -> UnsafeMutableRawPointer {
        let createDigitizer = try symbol("IOHIDEventCreateDigitizerEvent", as: CreateDigitizer.self)
        let createFinger = try symbol("IOHIDEventCreateDigitizerFingerEventWithQuality", as: CreateFinger.self)
        let append = try symbol("IOHIDEventAppendEvent", as: AppendEvent.self)
        let setInteger = try symbol("IOHIDEventSetIntegerValueWithOptions", as: SetInteger.self)
        let setSenderID = try symbol("IOHIDEventSetSenderID", as: SetSenderID.self)
        let time = mach_absolute_time()
        let displayIntegrated: UInt32 = (11 << 16) | 25
        let options: UInt32 = 0xF000_0000
        // 누름·뗌은 범위·접촉 변화(0x1 | 0x2), 끄는 중에는 위치 변화(0x4)
        let rangeAndTouch: UInt32 = moving ? 0x4 : (0x1 | 0x2)
        guard let hand = createDigitizer(kCFAllocatorDefault, time, 3, 0, 0, rangeAndTouch, 0, 0, 0, 0, 0, 0, touching, touching, 0),
              let finger = createFinger(kCFAllocatorDefault, time, 1, 2, rangeAndTouch, Double(point.x), Double(point.y), 0, 0, 0,
                                        5, 5, 1, 1, 1, touching, touching, 0) else {
            throw Failure.unavailable("IOHIDEvent 생성")
        }
        setInteger(hand, displayIntegrated, 1, options)
        setInteger(finger, displayIntegrated, 1, options)
        append(hand, finger, 0)
        // SwiftUI 제스처는 보낸 장치(sender)가 없는 이벤트를 무시하므로 가짜 ID를 넣는다.
        setSenderID(hand, 0x0000_0001_2345_6789)
        return hand
    }

    // MARK: - 비공개 메서드 호출(값 인자)

    private static func implementation(_ object: NSObject, _ name: String) throws -> (IMP, Selector) {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { throw Failure.unavailable(name) }
        return (object.method(for: selector), selector)
    }

    private static func call(_ object: NSObject, _ name: String, _ value: Int) throws {
        let (imp, selector) = try implementation(object, name)
        unsafeBitCast(imp, to: (@convention(c) (NSObject, Selector, Int) -> Void).self)(object, selector, value)
    }

    private static func callBool(_ object: NSObject, _ name: String, _ value: Bool) throws {
        let (imp, selector) = try implementation(object, name)
        unsafeBitCast(imp, to: (@convention(c) (NSObject, Selector, Bool) -> Void).self)(object, selector, value)
    }

    private static func callDouble(_ object: NSObject, _ name: String, _ value: Double) throws {
        let (imp, selector) = try implementation(object, name)
        unsafeBitCast(imp, to: (@convention(c) (NSObject, Selector, Double) -> Void).self)(object, selector, value)
    }

    private static func callPointer(_ object: NSObject, _ name: String, _ value: UnsafeMutableRawPointer) throws {
        let (imp, selector) = try implementation(object, name)
        unsafeBitCast(imp, to: (@convention(c) (NSObject, Selector, UnsafeMutableRawPointer) -> Void).self)(object, selector, value)
    }

    private static func callPointBool(_ object: NSObject, _ name: String, _ point: CGPoint, _ flag: Bool) throws {
        let (imp, selector) = try implementation(object, name)
        unsafeBitCast(imp, to: (@convention(c) (NSObject, Selector, CGPoint, Bool) -> Void).self)(object, selector, point, flag)
    }

    private static func callObjectBool(_ object: NSObject, _ name: String, _ value: NSObject, _ flag: Bool) throws {
        let (imp, selector) = try implementation(object, name)
        unsafeBitCast(imp, to: (@convention(c) (NSObject, Selector, NSObject, Bool) -> Void).self)(object, selector, value, flag)
    }
}
