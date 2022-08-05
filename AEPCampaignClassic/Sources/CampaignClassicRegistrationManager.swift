/*
 Copyright 2022 Adobe. All rights reserved.
 This file is licensed to you under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License. You may obtain a copy
 of the License at http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software distributed under
 the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
 OF ANY KIND, either express or implied. See the License for the specific language
 governing permissions and limitations under the License.
 */

import Foundation
import AEPServices
import AEPCore

class CampaignClassicRegistrationManager {

    let datastore = NamedCollectionDataStore(name: CampaignClassicConstants.EXTENSION_NAME)

    init() {

    }

    func registerDevice(withConfig configuration: CampaignClassicConfiguration, _ lifecycleData: [String: Any]?, _ event: Event) {
        guard let deviceToken = event.deviceToken else {
            Log.debug(label: CampaignClassicConstants.LOG_TAG, "Device Registration failed, device token is not available.")
            return
        }

        guard let integrationKey = configuration.integrationKey, let marketingServer = configuration.marketingServer else {
            Log.debug(label: CampaignClassicConstants.LOG_TAG, "Device Registration failed, `campaignclassic.ios.integrationKey` and/or campaignclassic.ios.marketingServer` configuration keys are unavailable.")
            return
        }

        if configuration.privacyStatus != PrivacyStatus.optedIn {
            Log.debug(label: CampaignClassicConstants.LOG_TAG, "Device Registration failed, MobilePrivacyStatus is not optedIn.")
            return
        }

        if !registrationInfoChanged(event, deviceToken, integrationKey, marketingServer) {
            Log.debug(label: CampaignClassicConstants.LOG_TAG, "Device Registration failed, there is no change in registration info since last successful request.")
            return
        }

        // prepare and send registration network request
        let payload = prepareRegistrationPayload(event, deviceToken, lifecycleData)
        let headers = [HttpConnectionConstants.Header.HTTP_HEADER_KEY_CONTENT_TYPE: HttpConnectionConstants.Header.HTTP_HEADER_CONTENT_TYPE_WWW_FORM_URLENCODED + ";" + CampaignClassicConstants.HEADER_CONTENT_TYPE_UTF8_CHARSET, CampaignClassicConstants.HEADER_KEY_CONTENT_LENGTH: String(payload.count)]
        let urlString = String(format: CampaignClassicConstants.REGISTRATION_API_URL_BASE, marketingServer)
        guard let url = URL(string: urlString) else {
            Log.debug(label: CampaignClassicConstants.LOG_TAG, "Device Registration failed, Invalid network request URL : \(urlString)")
            return
        }

        let request = NetworkRequest(url: url, httpMethod: .post, connectPayload: payload, httpHeaders: headers, connectTimeout: configuration.timeout, readTimeout: configuration.timeout)
        ServiceProvider.shared.networkService.connectAsync(networkRequest: request, completionHandler: { connection in
            if connection.responseCode == 200 {
                Log.debug(label: CampaignClassicConstants.LOG_TAG, "Device Registration success. URL : \(url.absoluteString)")
            }

            Log.debug(label: CampaignClassicConstants.LOG_TAG, "Device Registration failed, Network Error. Response Code: \(String(describing: connection.responseCode)) URL : \(url.absoluteString)")
        })

        return
    }

    private func registrationInfoChanged(_ event: Event,
                                         _ deviceToken: String,
                                         _ integrationKey: String,
                                         _ marketingServer: String) -> Bool {
        return false
    }

    private func prepareRegistrationPayload(_ event: Event,
                                            _ deviceToken: String,
                                            _ lifecycleData: [String: Any]?) -> String {
        return ""
    }

}
