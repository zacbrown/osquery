/**
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under both the Apache 2.0 license (found in the
 *  LICENSE file in the root directory of this source tree) and the GPLv2 (found
 *  in the COPYING file in the root directory of this source tree).
 *  You may select, at your option, one of the above-listed licenses.
 */

#include <osquery/flags.h>
#include <osquery/logger.h>
#include <osquery/registry_factory.h>

namespace osquery {

class StdoutLoggerPlugin : public LoggerPlugin {
 public:
  bool usesLogStatus() override {
    return true;
  }

 protected:
  Status logString(const std::string& s) override;

  void init(const std::string& name,
            const std::vector<StatusLogLine>& log) override;

  Status logStatus(const std::vector<StatusLogLine>& log) override;
};

REGISTER(StdoutLoggerPlugin, "logger", "stdout");

Status StdoutLoggerPlugin::logString(const std::string& s) {
  printf("%s\n", s.c_str());
  return Status();
}

Status StdoutLoggerPlugin::logStatus(const std::vector<StatusLogLine>& log) {
  for (const auto& item : log) {
    std::string line = "severity=" + std::to_string(item.severity) +
                       " location=" + item.filename + ":" +
                       std::to_string(item.line) + " message=" + item.message;

    printf("%s\n", line.c_str());
  }
  return Status();
}

void StdoutLoggerPlugin::init(const std::string& name,
                              const std::vector<StatusLogLine>& log) {
  // Stop the internal Glog facilities.
  FLAGS_alsologtostderr = false;
  FLAGS_logtostderr = false;
  FLAGS_stderrthreshold = 5;

  // Now funnel the intermediate status logs provided to `init`.
  logStatus(log);
}
}
