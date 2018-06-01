/**
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under both the Apache 2.0 license (found in the
 *  LICENSE file in the root directory of this source tree) and the GPLv2 (found
 *  in the COPYING file in the root directory of this source tree).
 *  You may select, at your option, one of the above-listed licenses.
 */

#include <boost/algorithm/string/trim.hpp>

#include <osquery/core.h>
#include <osquery/database.h>
#include <osquery/enroll.h>
#include <osquery/filesystem.h>
#include <osquery/flags.h>
#include <osquery/registry_factory.h>
#include <osquery/sql.h>
#include <osquery/system.h>

#include "osquery/core/process.h"

namespace pt = boost::property_tree;

namespace osquery {

/// At startup, always do a new enrollment instead of using a cached one
CLI_FLAG(bool,
         enroll_always,
         false,
         "On startup, send a new enrollment request");

/// Allow users to disable enrollment features.
CLI_FLAG(bool,
         disable_enrollment,
         false,
         "Disable enrollment functions on related config/logger plugins");

/// Path to optional enrollment secret data, sent with enrollment requests.
CLI_FLAG(string,
         enroll_secret_path,
         "",
         "Path to an optional client enrollment-auth secret");

/// Name of optional environment variable holding enrollment secret data.
CLI_FLAG(string,
         enroll_secret_env,
         "",
         "Name of environment variable holding enrollment-auth secret");

/// Allow users to disable reenrollment if a config/logger endpoint fails.
CLI_FLAG(bool,
         disable_reenrollment,
         false,
         "Disable re-enrollment attempts if related plugins return invalid");

/**
 * @brief Enroll plugin registry.
 *
 * This creates an osquery registry for "enroll" which may implement
 * EnrollPlugin. Only strings are logged in practice, and EnrollPlugin
 * provides a helper member for transforming PluginRequests to strings.
 */
CREATE_LAZY_REGISTRY(EnrollPlugin, "enroll");

const std::set<std::string> kEnrollHostDetails{
    "os_version", "osquery_info", "system_info", "platform_info",
};

Status clearNodeKey() {
  return deleteDatabaseValue(kPersistentSettings, "nodeKey");
}

std::string getNodeKey(const std::string& enroll_plugin) {
  std::string node_key;
  getDatabaseValue(kPersistentSettings, "nodeKey", node_key);
  if (node_key.size() > 0) {
    // A non-empty node key was found in the backing-store (cache).
    return node_key;
  }

  // The node key request time is recorded before the enroll request occurs.
  auto request_time = std::to_string(getUnixTime());

  // Request the enroll plugin's node secret.
  PluginResponse response;
  Registry::call("enroll", enroll_plugin, {{"action", "enroll"}}, response);
  if (response.size() > 0 && response[0].count("node_key") != 0) {
    node_key = response[0].at("node_key");
    setDatabaseValue(kPersistentSettings, "nodeKey", node_key);
    // Set the last time a nodeKey was requested from an enrollment endpoint.
    setDatabaseValue(kPersistentSettings, "nodeKeyTime", request_time);
  }
  return node_key;
}

const std::string getEnrollSecret() {
  std::string enrollment_secret;

  if (FLAGS_enroll_secret_path != "") {
    readFile(FLAGS_enroll_secret_path, enrollment_secret);
    boost::trim(enrollment_secret);
  } else {
    auto env_secret = getEnvVar(FLAGS_enroll_secret_env);
    if (env_secret.is_initialized()) {
      enrollment_secret = *env_secret;
    }
  }

  return enrollment_secret;
}

void EnrollPlugin::genHostDetails(JSON& host_details) {
  // Select from each table describing host details.
  for (const auto& table : kEnrollHostDetails) {
    auto results = SQL::selectAllFrom(table);
    if (!results.empty()) {
      JSON details;
      for (const auto& detail : results[0]) {
        details.add(detail.first, detail.second);
      }
      host_details.add(table, details.doc());
    }
  }
}

Status EnrollPlugin::call(const PluginRequest& request,
                          PluginResponse& response) {
  if (FLAGS_disable_enrollment) {
    return Status(0, "Enrollment disabled");
  }

  // Only support the 'enroll' action.
  if (request.count("action") == 0 || request.at("action") != "enroll") {
    return Status(1, "Enroll plugins require an action");
  }

  // The 'enroll' API should return a string and implement caching.
  auto node_key = this->enroll();
  response.push_back({{"node_key", node_key}});
  if (node_key.size() == 0) {
    return Status(1, "No enrollment key found/retrieved");
  } else {
    return Status(0, "OK");
  }
}
}
