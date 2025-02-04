// ===================================================================================================
// Copyright (C) 2017 Kaltura Inc.
//
// Licensed under the AGPLv3 license, unless a different license for a 
// particular library is specified in the applicable library path.
//
// You may obtain a copy of the License at
// https://www.gnu.org/licenses/agpl-3.0.html
// ===================================================================================================

import UIKit
import KalturaNetKit
import PlayKit

public class PhoenixAnalyticsPlugin: BaseOTTAnalyticsPlugin {
    
    public override class var pluginName: String { return "PhoenixAnalytics" }
    
    var config: PhoenixAnalyticsPluginConfig! {
        didSet {
            self.interval = config.timerInterval
            self.disableMediaHit = config.disableMediaHit
            self.disableMediaMark = config.disableMediaMark
            self.isExperimentalLiveMediaHit = config.isExperimentalLiveMediaHit
        }
    }
    
    public required init(player: Player, pluginConfig: Any?, messageBus: MessageBus) throws {
        try super.init(player: player, pluginConfig: pluginConfig, messageBus: messageBus)
        guard let config = pluginConfig as? PhoenixAnalyticsPluginConfig else {
            PKLog.error("missing/wrong plugin config")
            throw PKPluginError.missingPluginConfig(pluginName: PhoenixAnalyticsPlugin.pluginName)
        }
        self.config = config
    }
    
    public override func onUpdateConfig(pluginConfig: Any) {
        super.onUpdateConfig(pluginConfig: pluginConfig)
        
        guard let config = pluginConfig as? PhoenixAnalyticsPluginConfig else {
            PKLog.error("plugin config is wrong")
            return
        }
        
        PKLog.debug("new config::\(String(describing: config))")
        self.config = config
    }
    
    /************************************************************/
    // MARK: - KalturaOTTAnalyticsPluginProtocol
    /************************************************************/
    
    override func buildRequest(ofType type: OTTAnalyticsEventType) -> Request? {
        guard !config.ks.isEmpty else {
            PKLog.debug("Analytics not sent, ks is empty.")
            return nil
        }
        
        var currentTime: Int32 = 0
        
        if type == .stop {
            currentTime = self.lastPosition
        } else {
            guard let player = self.player else {
                PKLog.error("Send analytics failed due to nil associated player.")
                return nil
            }
            
            currentTime = player.currentTime.toInt32()
        }
        
        var assetType = ""
        if let metadata = self.player?.mediaEntry?.metadata, let type = metadata["assetType"] {
            assetType = type
        }
        
        if let metadataRecordingId = self.player?.mediaEntry?.metadata, let mediaRecordingId = metadataRecordingId["recordingId"] {
            mediaId = mediaRecordingId
        }
  
        var epgId: String?
        if let bookmarkEpgId = config.epgId, !bookmarkEpgId.isEmpty {
            epgId = bookmarkEpgId
        } else if let metadataEpgId = self.player?.mediaEntry?.metadata, let mediaEpgId = metadataEpgId["epgId"] {
            epgId = mediaEpgId
        }
        
        guard let requestBuilder: KalturaRequestBuilder = BookmarkService.actionAdd(baseURL: config.baseUrl,
                                                                                    partnerId: config.partnerId,
                                                                                    ks: config.ks,
                                                                                    eventType: type.rawValue.uppercased(),
                                                                                    currentTime: currentTime,
                                                                                    assetId: mediaId ?? "",
                                                                                    epgId: epgId,
                                                                                    assetType: assetType,
                                                                                    fileId: fileId ?? "") else { return nil }
        
        requestBuilder.set { (response: Response) in
            PKLog.debug("Response: \(response)")
            if response.statusCode == 0 {
                PKLog.verbose("\(String(describing: response.data))")
                guard let data = response.data as? [String: Any] else { return }
                guard let result = data["result"] as? [String: Any] else { return }
                guard let ottError = OTTError(json: result) else { return }
                
                switch ottError.code {
                case "4001":
                    self.reportConcurrencyEvent()
                default:
                    self.reportBookmarkErrorEvent(code: ottError.code, message: ottError.message)
                }
            }
        }
        
        return requestBuilder.build()
    }
}
