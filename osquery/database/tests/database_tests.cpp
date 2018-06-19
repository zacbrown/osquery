/**
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under both the Apache 2.0 license (found in the
 *  LICENSE file in the root directory of this source tree) and the GPLv2 (found
 *  in the COPYING file in the root directory of this source tree).
 *  You may select, at your option, one of the above-listed licenses.
 */

#include <gtest/gtest.h>

#include <osquery/database.h>

#include "osquery/core/json.h"
#include "osquery/tests/test_util.h"

#include <osquery/logger.h>

#include <limits>

namespace rj = rapidjson;

namespace osquery {

class DatabaseTests : public testing::Test {};

TEST_F(DatabaseTests, test_set_value_str) {
  auto s = setDatabaseValue(kLogs, "str", "{}");
  EXPECT_TRUE(s.ok());
}

TEST_F(DatabaseTests, test_set_value_int) {
  auto s = setDatabaseValue(kLogs, "int", -1);
  EXPECT_TRUE(s.ok());
}

TEST_F(DatabaseTests, test_set_value_mix1) {
  auto s = setDatabaseValue(kLogs, "intstr", -1);
  EXPECT_TRUE(s.ok());

  s = setDatabaseValue(kLogs, "intstr", "{}");
  EXPECT_TRUE(s.ok());
}

TEST_F(DatabaseTests, test_set_value_mix2) {
  auto s = setDatabaseValue(kLogs, "strint", "{}");
  EXPECT_TRUE(s.ok());

  s = setDatabaseValue(kLogs, "strint", -1);
  EXPECT_TRUE(s.ok());
}

TEST_F(DatabaseTests, test_get_value_does_not_exist) {
  // Unknown keys return failed, but will return empty data.
  std::string value;
  auto s = getDatabaseValue(kLogs, "does_not_exist", value);
  EXPECT_FALSE(s.ok());
  EXPECT_TRUE(value.empty());
}

TEST_F(DatabaseTests, test_get_value_str) {
  std::string expected;
  for (unsigned char i = std::numeric_limits<unsigned char>::min();
       i < std::numeric_limits<unsigned char>::max();
       i++) {
    if (std::isprint(i)) {
      expected += i;
    }
  }

  setDatabaseValue(kLogs, "str", expected);

  std::string value;
  auto s = getDatabaseValue(kLogs, "str", value);

  EXPECT_TRUE(s.ok());
  EXPECT_EQ(value, expected);
}

TEST_F(DatabaseTests, test_get_value_int) {
  int expected = std::numeric_limits<int>::min();
  setDatabaseValue(kLogs, "int", expected);

  int value = 0;
  auto s = getDatabaseValue(kLogs, "int", value);

  EXPECT_TRUE(s.ok());
  EXPECT_EQ(value, expected);
}

TEST_F(DatabaseTests, test_get_value_mix1) {
  int expected = std::numeric_limits<int>::max();
  setDatabaseValue(kLogs, "strint", "{}");
  setDatabaseValue(kLogs, "strint", expected);

  int value;
  auto s = getDatabaseValue(kLogs, "strint", value);

  EXPECT_TRUE(s.ok());
  EXPECT_EQ(value, expected);
}

TEST_F(DatabaseTests, test_get_value_mix2) {
  std::string expected = "{}";
  setDatabaseValue(kLogs, "intstr", -1);
  setDatabaseValue(kLogs, "intstr", expected);

  std::string value;
  auto s = getDatabaseValue(kLogs, "intstr", value);

  EXPECT_TRUE(s.ok());
  EXPECT_EQ(value, expected);
}

TEST_F(DatabaseTests, test_scan_values) {
  setDatabaseValue(kLogs, "1", "0");
  setDatabaseValue(kLogs, "2", 0);
  setDatabaseValue(kLogs, "3", "0");

  std::vector<std::string> keys;
  auto s = scanDatabaseKeys(kLogs, keys);
  EXPECT_TRUE(s.ok());
  EXPECT_GT(keys.size(), 2U);

  keys.clear();
  s = scanDatabaseKeys(kLogs, keys, 3);
  EXPECT_TRUE(s.ok());
  EXPECT_EQ(keys.size(), 3U);
}

TEST_F(DatabaseTests, test_delete_values_str) {
  setDatabaseValue(kLogs, "k", "0");

  std::string value;
  getDatabaseValue(kLogs, "k", value);
  EXPECT_FALSE(value.empty());

  auto s = deleteDatabaseValue(kLogs, "k");
  EXPECT_TRUE(s.ok());

  // Make sure the key has been deleted.
  value.clear();
  s = getDatabaseValue(kLogs, "k", value);
  EXPECT_FALSE(s.ok());
  EXPECT_TRUE(value.empty());
}

TEST_F(DatabaseTests, test_delete_values_int) {
  int expected = 0;
  setDatabaseValue(kLogs, "k", expected);

  int value;
  getDatabaseValue(kLogs, "k", value);
  EXPECT_EQ(value, expected);

  auto s = deleteDatabaseValue(kLogs, "k");
  EXPECT_TRUE(s.ok());

  // Make sure the key has been deleted.
  value = -5;
  s = getDatabaseValue(kLogs, "k", value);
  EXPECT_FALSE(s.ok());
  EXPECT_EQ(value, -5);
}

TEST_F(DatabaseTests, test_ptree_upgrade_to_rj_empty_v0v1) {
  auto empty_results{"{}"};
  auto status = setDatabaseValue(kQueries, "old_empty_results", empty_results);
  EXPECT_TRUE(status.ok());

  // Stage our database to be pre-upgrade to ensure the logic runs
  status = setDatabaseValue(kPersistentSettings, "results_version", "0");
  EXPECT_TRUE(status.ok());

  status = upgradeDatabase();
  EXPECT_TRUE(status.ok());

  std::string new_empty_list;
  status = getDatabaseValue(kQueries, "old_empty_results", new_empty_list);
  EXPECT_TRUE(status.ok());

  rj::Document empty_list;
  EXPECT_FALSE(empty_list.Parse(new_empty_list).HasParseError());
  EXPECT_TRUE(empty_list.IsArray());

  // Expect our DB upgrade logic to have been set
  std::string db_results_version{""};
  getDatabaseValue(kPersistentSettings, "results_version", db_results_version);
  EXPECT_EQ(db_results_version, kDatabaseResultsVersion);
}

TEST_F(DatabaseTests, test_ptree_upgrade_to_rj_results_v0v1) {
  auto bad_json =
      "{\"\":{\"disabled\":\"0\",\"network_name\":\"BTWifi-Starbucks\"},\"\":{"
      "\"disabled\":\"0\",\"network_name\":\"Lobo-Guest\"},\"\":{\"disabled\":"
      "\"0\",\"network_name\":\"GoogleGuest\"}}";
  auto status = setDatabaseValue(kQueries, "bad_wifi_json", bad_json);
  EXPECT_TRUE(status.ok());

  // Add an integer value to ensure we don't munge non-json objects
  status = setDatabaseValue(kQueries, "bad_wifi_jsonepoch", "1521583712");
  EXPECT_TRUE(status.ok());

  // Stage our database to be pre-upgrade to ensure the logic runs
  status = setDatabaseValue(kPersistentSettings, "results_version", "0");
  EXPECT_TRUE(status.ok());

  rj::Document bad_doc;

  // Potential bug with RJ, in that parsing should fail with empty keys
  // EXPECT_TRUE(bad_doc.Parse(bad_json).HasParseError());
  EXPECT_FALSE(bad_doc.IsArray());

  status = upgradeDatabase();
  EXPECT_TRUE(status.ok());

  std::string good_json;
  status = getDatabaseValue(kQueries, "bad_wifi_json", good_json);
  EXPECT_TRUE(status.ok());

  rj::Document clean_doc;
  EXPECT_FALSE(clean_doc.Parse(good_json).HasParseError());
  EXPECT_TRUE(clean_doc.IsArray());
  EXPECT_EQ(clean_doc.Size(), 3U);

  // Ensure our non-json thing was not destroyed
  std::string query_epoch{""};
  status = getDatabaseValue(kQueries, "bad_wifi_jsonepoch", query_epoch);
  LOG(INFO) << query_epoch;
  auto ulepoch = std::stoull(query_epoch);
  EXPECT_EQ(ulepoch, 1521583712U);

  // Expect our DB upgrade logic to have been set
  std::string db_results_version{""};
  getDatabaseValue(kPersistentSettings, "results_version", db_results_version);
  EXPECT_EQ(db_results_version, kDatabaseResultsVersion);
}
}
