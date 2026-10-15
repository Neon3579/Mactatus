// 비공식: IOKit의 IOHIDEventSystemClient(비공개 함수)로 온도 센서를 읽는다. macOS 27.0.1 · M2에서 확인.
// 함수가 없거나 실패하면 nil을 돌려주고, 화면은 온도 항목을 숨긴다.
import Darwin
import Foundation

final class TemperatureSensors {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatchingFn = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias CopyServicesFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (AnyObject, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEventFn = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatFn = @convention(c) (AnyObject, Int32) -> Double

    private static let temperatureEvent: Int64 = 15

    private var copyEvent: CopyEventFn?
    private var getFloat: GetFloatFn?
    /// SoC 다이 센서("PMU tdie…")만 골라 둔다.
    private var dieSensors: [AnyObject] = []
    private var client: AnyObject?

    init() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return }
        func load<T>(_ name: String, _ type: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }
        guard let create = load("IOHIDEventSystemClientCreate", CreateFn.self),
              let setMatching = load("IOHIDEventSystemClientSetMatching", SetMatchingFn.self),
              let copyServices = load("IOHIDEventSystemClientCopyServices", CopyServicesFn.self),
              let copyProperty = load("IOHIDServiceClientCopyProperty", CopyPropertyFn.self),
              let copyEvent = load("IOHIDServiceClientCopyEvent", CopyEventFn.self),
              let getFloat = load("IOHIDEventGetFloatValue", GetFloatFn.self),
              let client = create(kCFAllocatorDefault)?.takeRetainedValue() else { return }
        // Apple 벤더 페이지(0xff00)의 온도 센서(usage 5)
        setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        let services = (copyServices(client)?.takeRetainedValue() as? [AnyObject]) ?? []
        // 다이 센서는 16개쯤 되지만 하나 읽는 데 1ms가 넘게 걸려서, 고르게 4개만 쓴다
        let die = services.filter { service in
            let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String ?? ""
            return name.contains("tdie")
        }
        let stride = Swift.max(die.count / 4, 1)
        dieSensors = Swift.stride(from: 0, to: die.count, by: stride).prefix(4).map { die[$0] }
        self.client = client
        self.copyEvent = copyEvent
        self.getFloat = getFloat
    }

    /// (평균, 최댓값) ℃. 말이 안 되는 값(0 이하, 150 이상)은 뺀다.
    func socTemperature() -> (average: Double, max: Double)? {
        guard let copyEvent, let getFloat, !dieSensors.isEmpty else { return nil }
        let values = dieSensors.compactMap { service -> Double? in
            guard let event = copyEvent(service, Self.temperatureEvent, 0, 0)?.takeRetainedValue() else { return nil }
            let value = getFloat(event, Int32(Self.temperatureEvent << 16))
            return value > 0 && value < 150 ? value : nil
        }
        guard let max = values.max() else { return nil }
        return (values.reduce(0, +) / Double(values.count), max)
    }
}
