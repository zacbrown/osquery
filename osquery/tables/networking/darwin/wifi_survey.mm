/**
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under both the Apache 2.0 license (found in the
 *  LICENSE file in the root directory of this source tree) and the GPLv2 (found
 *  in the COPYING file in the root directory of this source tree).
 *  You may select, at your option, one of the above-listed licenses.
 */

#include <CoreWLAN/CoreWLAN.h>
#include <Foundation/Foundation.h>

#include <osquery/system.h>
#include <osquery/tables.h>

#include "osquery/tables/networking/darwin/wifi_utils.h"

namespace osquery {
namespace tables {

QueryData genWifiScan(QueryContext& context) {
  QueryData results;
  @autoreleasepool {
    NSArray<CWInterface*>* interfaces =
        [[CWWiFiClient sharedWiFiClient] interfaces];
    if (interfaces == nil || [interfaces count] == 0) {
      return results;
    }
    for (CWInterface* interface in interfaces) {
      NSSet<CWNetwork*>* networks =
          [interface scanForNetworksWithName:nil error:nil];

      for (CWNetwork* network in networks) {
        Row r;
        r["interface"] = std::string([[interface interfaceName] UTF8String]);
        r["ssid"] = extractSsid((__bridge CFDataRef)[network ssidData]);
        r["bssid"] = std::string([[network bssid] UTF8String]);
        r["network_name"] = std::string([[network ssid] UTF8String]);
        NSString* country_code = [network countryCode];
        if (country_code != nil) {
          r["country_code"] = std::string([country_code UTF8String]);
        }
        r["rssi"] = INTEGER([network rssiValue]);
        r["noise"] = INTEGER([network noiseMeasurement]);
        CWChannel* cwc = [network wlanChannel];
        if (cwc != nil) {
          r["channel"] = INTEGER(getChannelNumber(cwc));
          r["channel_width"] = INTEGER(getChannelWidth(cwc));
          r["channel_band"] = INTEGER(getChannelBand(cwc));
        }
        results.push_back(r);
      }
    }
  }
  return results;
}
}
}
