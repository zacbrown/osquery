/**
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under both the Apache 2.0 license (found in the
 *  LICENSE file in the root directory of this source tree) and the GPLv2 (found
 *  in the COPYING file in the root directory of this source tree).
 *  You may select, at your option, one of the above-listed licenses.
 */

#pragma once

#include <ctime>
#include <memory>
#include <string>

#include <boost/filesystem/path.hpp>

#include <osquery/core.h>

namespace osquery {

/// The osquery platform agnostic process identifier type.
using PlatformPidType = pid_t;

class DropPrivileges;
using DropPrivilegesRef = std::shared_ptr<DropPrivileges>;

class DropPrivileges : private boost::noncopyable {
 public:
  /// Make call sites use 'dropTo' booleans to improve the UI.
  static DropPrivilegesRef get();

  /**
   * @brief Attempt to drop privileges to that of the parent of a given path.
   *
   * This will return false if privileges could not be dropped or there was
   * an previous, and still active, request for dropped privileges.
   *
   * @return success if privileges were dropped, otherwise false.
   */
  bool dropToParent(const boost::filesystem::path& path);

  /// See DropPrivileges::dropToParent but explicitiy set the UID and GID.
  bool dropTo(const std::string& uid, const std::string& gid);

  /// See DropPrivileges::dropToParent but explicitly set the UID and GID.
  bool dropTo(uid_t uid, gid_t gid);

  /// See DropPrivileges::dropToParent but for a user's UID and GID.
  bool dropTo(const std::string& user);

  /// Check if effective privileges do not match real.
  bool dropped() {
    return (getuid() != geteuid() || getgid() != getegid());
  }

  /**
   * @brief The privilege/permissions dropper deconstructor will restore
   * effective permissions.
   *
   * There should only be a single drop of privilege/permission active.
   */
  virtual ~DropPrivileges();

 private:
  DropPrivileges() = default;

  /// Restore groups if dropping consecutively.
  void restoreGroups();

 private:
  /// Boolean to track if this instance needs to restore privileges.
  bool dropped_{false};

  /// The user this instance dropped privileges to.
  uid_t to_user_{0};

  /// The group this instance dropped privileges to.
  gid_t to_group_{0};

  /**
   * @brief If dropping explicitly to a user and group also drop groups.
   *
   * Original process groups before explicitly dropping privileges.
   * On restore, if there are any groups in this list, they will be added
   * to the processes group list.
   */
  gid_t* original_groups_{nullptr};

  /// The size of the original groups to backup when restoring privileges.
  size_t group_size_{0};

 private:
  FRIEND_TEST(PermissionsTests, test_explicit_drop);
  FRIEND_TEST(PermissionsTests, test_path_drop);
  FRIEND_TEST(PermissionsTests, test_nobody_drop);
};
} // namespace osquery
