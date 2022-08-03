/*
 Copyright 2022 Adobe. All rights reserved.
 This file is licensed to you under the Apache License, Version 2.0 (the "License")
 you may not use this file except in compliance with the License. You may obtain a copy
 of the License at http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software distributed under
 the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
 OF ANY KIND, either express or implied. See the License for the specific language
 governing permissions and limitations under the License.
 */

import AEPCore
import AEPServices
import Foundation
import UIKit

@objc(AEPMobileCampaignClassic)
public class CampaignClassic: NSObject, Extension {
    public let name = CampaignClassicConstants.EXTENSION_NAME
    public let friendlyName = CampaignClassicConstants.FRIENDLY_NAME
    public static let extensionVersion = CampaignClassicConstants.EXTENSION_VERSION
    public var metadata: [String: String]?
    public var runtime: ExtensionRuntime
    
    var state: CampaignClassicState
    let registrationManager : CampaignClassicRegistrationManager
    let dispatchQueue: DispatchQueue
    
    
    
    private var networkService: Networking {
        return ServiceProvider.shared.networkService
    }

    /// Initializes the Campaign Classic extension
    public required init?(runtime: ExtensionRuntime) {
        self.runtime = runtime
        self.registrationManager = CampaignClassicRegistrationManager()
        dispatchQueue = DispatchQueue(label: "\(CampaignClassicConstants.EXTENSION_NAME).dispatchqueue")
        self.state = CampaignClassicState()
        super.init()
    }

    /// Invoked when the Campaign Classic extension has been registered by the `EventHub`
    public func onRegistered() {
        registerListener(type: EventType.configuration, source: EventSource.responseContent, listener: handleConfigurationEvents)
        registerListener(type: CampaignClassicConstants.SDKEventType.CAMPAIGN_CLASSIC, source: EventSource.requestContent, listener: handleConfigurationEvents)
    }

    /// Invoked when the CampaignClassic extension has been unregistered by the `EventHub`, currently a no-op.
    public func onUnregistered() {}

    /// Called before each `Event` processed by the Campaign Classic extension
    /// - Parameter event: event that will be processed next
    /// - Returns: `true` if Configuration shared state is available
    public func readyForEvent(_ event: Event) -> Bool {
        guard let configurationSharedState = getSharedState(extensionName: CampaignClassicConstants.EventDataKeys.Configuration.NAME, event: event) else {
            Log.debug(label: CampaignClassicConstants.LOG_TAG, "Event processing is paused, waiting for valid configuration - '\(event.id.uuidString)'.")
            return false
        }
        return configurationSharedState.status == .set
    }
    
    /// Handles `Configuration Response` events
    /// - Parameter event: the Configuration `Event` to be handled
    private func handleCampaignClassicEvents(event: Event) {
        Log.trace(label: CampaignClassicConstants.LOG_TAG, "An event of type '\(event.type)' has been received.")
        dispatchQueue.async { [weak self] in
            guard let self = self else {return}
            
            if event.isRegisterEvent {
                self.handleRegisterDeviceEvent(event: event)
            } else if event.isTrackClickEvent {
                self.handleTrackEvent(event: event, withTagId: CampaignClassicConstants.TRACK_CLICK_TAGID)
            } else if event.isTrackReceiveEvent {
                self.handleTrackEvent(event: event, withTagId: CampaignClassicConstants.TRACK_RECEIVE_TAGID)
            }
        }
    }
    
    private func handleRegisterDeviceEvent(event: Event) {
        let lifecycleData = runtime.getSharedState(extensionName: CampaignClassicConstants.EventDataKeys.Lifecycle.EXTENSION_NAME, event: event, barrier: false)?.value
        let configuration = CampaignClassicConfiguration.init(forEvent: event, runtime: runtime)
        let status = registrationManager.registerDevice(withConfig: configuration, lifecycleData ,event)
    }
    
    private func handleTrackEvent(event: Event, withTagId tagId : String) {
        let configuration = CampaignClassicConfiguration.init(forEvent: event, runtime: runtime)
        
        guard let trackingServer = configuration.trackingServer else {
            Log.debug(label: CampaignClassicConstants.LOG_TAG, "Unable to process TrackNotification request, Configuration not available.")
            return
        }
        
        if configuration.privacyStatus != PrivacyStatus.optedIn {
            Log.debug(label: CampaignClassicConstants.LOG_TAG, "Unable to process TrackNotification request, MobilePrivacyStatus is not optedIn.")
            return
        }
                
        guard let deliveryId = event.deliveryId else {
            Log.debug(label: CampaignClassicConstants.LOG_TAG, "Unable to process TrackNotification request, trackingInfo deliveryId is nil (missing key `_dId` from tracking Info).")
            return
        }
        
        guard let broadlogId = event.broadlogId else {
            Log.debug(label: CampaignClassicConstants.LOG_TAG, "Unable to process TrackNotification request, trackingInfo broadLogId is nil (missing key `_mId` from tracking Info).")
            return
        }
        
        guard let transformedBroadlogId = transformBroadLogId(broadlogId) else {
            Log.debug(label: CampaignClassicConstants.LOG_TAG, "TrackingInfo broadLogId is nil (Missing key `_mId` from tracking Info), discarding the campaign classic track event.")
            return
        }
        
        guard let trackingUrl = URL(string: String(format: CampaignClassicConstants.TRACKING_API_URL_BASE, trackingServer, transformedBroadlogId, deliveryId, tagId)) else {
            return
        }
        
        let request = NetworkRequest(url: trackingUrl, httpMethod: .get, connectPayload: "", httpHeaders: [:], connectTimeout: configuration.timeout, readTimeout: configuration.timeout)
        
        networkService.connectAsync(networkRequest: request, completionHandler: { connection in
            if connection.responseCode == 200 {
                Log.debug(label: CampaignClassicConstants.LOG_TAG, "TrackNotification success. URL : \(trackingUrl.absoluteString)")
            }
            
            Log.debug(label: CampaignClassicConstants.LOG_TAG, "Unable to trackNotification, Network Error. Response Code: \(String(describing: connection.responseCode)) URL : \(trackingUrl.absoluteString)")
        })
    }
    
    
    private func transformBroadLogId(_ broadlogId : String) -> String? {
        if let _ = UUID(uuidString: broadlogId) {
            return broadlogId
        }
        return broadlogId
    }

    /// Handles `Configuration Response` events
    /// - Parameter event: the Configuration `Event` to be handled
    private func handleConfigurationEvents(event: Event) {
        Log.trace(label: CampaignClassicConstants.LOG_TAG, "An event of type '\(event.type)' has been received.")
        dispatchQueue.async { [weak self] in
            guard let self = self else {return}
            self.updateCampaignState(event: event)
            // update CampaignClassicState
            if self.state.privacyStatus == PrivacyStatus.optedOut {
                // handle opt-out
                return
            }
        }
    }

    /// Updates the `CampaignClassicState` with the shared state of other required extensions
    /// - Parameter event: the `Event`containing the shared state of other required extensions
    private func updateCampaignState(event: Event) {
        // todo
    }
}


struct CampaignClassicConfiguration {
    var integrationKey : String?
    var marketingServer : String?
    var trackingServer : String?
    var timeout : TimeInterval = CampaignClassicConstants.Default.NETWORK_TIMEOUT
    var privacyStatus : PrivacyStatus = CampaignClassicConstants.Default.PRIVACY_STATUS
    
    init(forEvent event: Event,runtime : ExtensionRuntime){
            guard let configSharedState = runtime.getSharedState(extensionName: CampaignClassicConstants.EventDataKeys.Configuration.NAME, event: event, barrier: false)?.value else {
                return
            }
            
            integrationKey = configSharedState[CampaignClassicConstants.EventDataKeys.Configuration.CAMPAIGNCLASSIC_INTEGRATION_KEY] as? String
            marketingServer = configSharedState[CampaignClassicConstants.EventDataKeys.Configuration.CAMPAIGNCLASSIC_MARKETING_SERVER] as? String
            trackingServer = configSharedState[CampaignClassicConstants.EventDataKeys.Configuration.CAMPAIGNCLASSIC_TRACKING_SERVER] as? String
            timeout = configSharedState[CampaignClassicConstants.EventDataKeys.Configuration.CAMPAIGNCLASSIC_TRACKING_SERVER] as? TimeInterval ?? CampaignClassicConstants.Default.NETWORK_TIMEOUT
            let privacyStatusString = configSharedState[CampaignClassicConstants.EventDataKeys.Configuration.CAMPAIGNCLASSIC_TRACKING_SERVER] as? String ?? ""
            privacyStatus = PrivacyStatus.init(rawValue: configSharedState[CampaignClassicConstants.EventDataKeys.Configuration.GLOBAL_CONFIG_PRIVACY] as? PrivacyStatus.RawValue ?? CampaignClassicConstants.Default.PRIVACY_STATUS.rawValue) ?? CampaignClassicConstants.Default.PRIVACY_STATUS

            privacyStatus = PrivacyStatus(rawValue: privacyStatusString)!
        
    }
    
}
