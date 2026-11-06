import Orion
import insulationC

class CommonProductClassHook: ClassHook<CommonProduct> {
  func initProduct(_ arg: Any?) -> CommonProduct? {
    let res = orig.initProduct(arg);
    IPowerHepler.shared.commonProductObject = target;

    // 开关关闭或未充电：保持原插件初始化行为。
    // 开关开启且正在充电：不写入插件的 nominal 模式，让系统原生温控接管。
    if IPowerHepler.shared.shouldPluginBeActive() {
      target.putDevice(inThermalSimulationMode: "nominal");
    }

    IPowerHepler.shared.startChargingMonitorIfNeeded();
    return res;
  }

  // 插件生效时沿用原版屏蔽行为；插件应让位给苹果原生温控时，调用原实现。
  func tryTakeAction() {
    if !IPowerHepler.shared.shouldPluginBeActive() {
      orig.tryTakeAction();
    }
  }

  func simulateLightThermalPressure() {
    if !IPowerHepler.shared.shouldPluginBeActive() {
      orig.simulateLightThermalPressure();
    }
  }

  func updatePowerzoneTelemetry() {
    if !IPowerHepler.shared.shouldPluginBeActive() {
      orig.updatePowerzoneTelemetry();
    }
  }
}

class HidSensorsHook: ClassHook<HidSensors> {
  func handleTemperatureEvent(_ arg1: Int, service arg2: Any?) {
    if !IPowerHepler.shared.shouldPluginBeActive() {
      orig.handleTemperatureEvent(arg1, service: arg2);
    }
  }
}

class NSDictionaryHook: ClassHook<NSDictionary> {
  class func dictionaryWithContentsOfFile(_ path: String) -> Any? {
    let res = orig.dictionaryWithContentsOfFile(path);

    // 充电原生温控开启且检测到正在充电时，直接返回系统原始 plist，
    // 不再注入插件的温控参数。
    if !IPowerHepler.shared.shouldPluginBeActive() {
      return res;
    }

    if path.contains("/System/Library/ThermalMonitor/") {
      if let origObj = res as? [String: Any] {
        let obj = IDictHepler.shared.patchThermalPlist(origObj as CFDictionary);
        return obj;
      }
    }
    return res;
  }
}

class InsulationTInit: Tweak {
  required init() {
    let center = CFNotificationCenterGetDarwinNotifyCenter();
    let executePuppetEventName = "com.be-huge.insulation-executePuppetEvent" as CFString;
    let observer = UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque());
    CFNotificationCenterAddObserver(center, observer, { _, _, _, _, _ in
      IPowerHepler.shared.executePuppetEvent();
    }, executePuppetEventName, nil, .deliverImmediately);
  }
}