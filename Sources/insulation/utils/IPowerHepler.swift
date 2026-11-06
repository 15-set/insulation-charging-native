import Foundation
import IOKit.ps
import insulationC

class IPowerHepler {
  private init() {}

  static let shared = IPowerHepler();

  private(set) var plistObj: [String: Any] = [:];
  var commonProductObject: CommonProduct? = nil;

  private let monitorQueue = DispatchQueue(label: "com.be-huge.insulation.charging-native-monitor")
  private var monitorTimer: DispatchSourceTimer?
  private var lastChargingState: Bool?

  func getCPUMaxPower() -> Int {
    if self.plistObj.isEmpty {
      self.getLocalPrefValue();
    }
    let powerValue = (self.plistObj["cpuMinPowerValue"] as? String) ?? "";
    let num = Int(powerValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0;
    return num;
  }

  func getLocalPrefValue() {
    let plistValue = IFileManager.getPlistContent(
      withPath: insulationC.rootlessPath("/var/mobile/Library/Preferences/com.be-huge.insulation-prefs.plist")
    );
    self.plistObj = plistValue;
  }

  // IOKit 返回电源是否处于“正在充电”状态；满电但未充电时返回 false。
  func isBatteryCharging() -> Bool {
    guard let infoRef = IOPSCopyPowerSourcesInfo() else { return false }
    let info = infoRef.takeRetainedValue()
    guard let listRef = IOPSCopyPowerSourcesList(info) else { return false }
    let sources = listRef.takeRetainedValue() as Array

    for source in sources {
      guard let descriptionRef = IOPSGetPowerSourceDescription(info, source) else { continue }
      let description = descriptionRef.takeUnretainedValue() as NSDictionary
      if (description[kIOPSIsChargingKey as String] as? Bool) == true {
        return true
      }
    }
    return false
  }

  // 开关关闭：插件始终生效。开关打开：仅在“正在充电”时让插件让位。
  func shouldPluginBeActive() -> Bool {
    self.getLocalPrefValue()
    let automatic = (self.plistObj["chargingNativeThermalEnabled"] as? Bool) ?? false
    if !automatic {
      return true
    }
    return !self.isBatteryCharging()
  }

  private func applySelectedThermalMode() {
    self.getLocalPrefValue()
    let eventType = (self.plistObj["thermalPuppetValue"] as? String) ?? "nominal"
    if let direction = ThermalLevelEnum(rawValue: eventType) {
      direction.next()
    }
  }

  // 只在开关开启时运行监测；状态变化为“停止充电”时重新应用用户原来选择的模式。
  func startChargingMonitorIfNeeded() {
    self.getLocalPrefValue()
    let automatic = (self.plistObj["chargingNativeThermalEnabled"] as? Bool) ?? false

    monitorQueue.async {
      if !automatic {
        self.monitorTimer?.cancel()
        self.monitorTimer = nil
        self.lastChargingState = nil
        return
      }

      guard self.monitorTimer == nil else { return }

      let timer = DispatchSource.makeTimerSource(queue: self.monitorQueue)
      timer.schedule(deadline: .now(), repeating: .seconds(5))
      timer.setEventHandler { [weak self] in
        guard let self = self else { return }
        self.getLocalPrefValue()
        let enabled = (self.plistObj["chargingNativeThermalEnabled"] as? Bool) ?? false
        if !enabled {
          self.monitorTimer?.cancel()
          self.monitorTimer = nil
          self.lastChargingState = nil
          return
        }

        let charging = self.isBatteryCharging()
        if self.lastChargingState == nil {
          self.lastChargingState = charging
          if !charging {
            self.applySelectedThermalMode()
          }
        } else if self.lastChargingState != charging {
          self.lastChargingState = charging
          if !charging {
            self.applySelectedThermalMode()
          }
          // 开始充电时不写入任何模拟模式；所有 hook 同时改为透传系统原始实现。
        }
      }
      self.monitorTimer = timer
      timer.resume()
    }
  }

  func executePuppetEvent() {
    self.getLocalPrefValue()
    let automatic = (self.plistObj["chargingNativeThermalEnabled"] as? Bool) ?? false

    if automatic {
      self.startChargingMonitorIfNeeded()
      if !self.isBatteryCharging() {
        self.applySelectedThermalMode()
      }
      return
    }

    // 开关关闭：完全执行原版逻辑，不做充电状态判断。
    self.startChargingMonitorIfNeeded()
    let eventType = (self.plistObj["thermalPuppetValue"] as? String) ?? ""
    if let direction = ThermalLevelEnum(rawValue: eventType) {
      direction.next()
    }
  }
}
