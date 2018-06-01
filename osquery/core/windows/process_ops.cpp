/**
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under both the Apache 2.0 license (found in the
 *  LICENSE file in the root directory of this source tree) and the GPLv2 (found
 *  in the COPYING file in the root directory of this source tree).
 *  You may select, at your option, one of the above-listed licenses.
 */

#include "osquery/core/windows/process_ops.h"
#include "osquery/core/conversions.h"

namespace osquery {

std::string psidToString(PSID sid) {
  LPTSTR sidOut = nullptr;
  auto ret = ConvertSidToStringSidA(sid, &sidOut);
  if (ret == 0) {
    VLOG(1) << "ConvertSidToString failed with " << GetLastError();
    return std::string("");
  }
  return std::string(sidOut);
}

int getUidFromSid(PSID sid) {
  auto eUse = SidTypeUnknown;
  unsigned long unameSize = 0;
  unsigned long domNameSize = 1;

  // LookupAccountSid first gets the size of the username buff required.
  LookupAccountSidW(
      nullptr, sid, nullptr, &unameSize, nullptr, &domNameSize, &eUse);
  std::vector<wchar_t> uname(unameSize);
  std::vector<wchar_t> domName(domNameSize);
  auto ret = LookupAccountSidW(nullptr,
                               sid,
                               uname.data(),
                               &unameSize,
                               domName.data(),
                               &domNameSize,
                               &eUse);

  if (ret == 0) {
    return -1;
  }
  // USER_INFO_3 struct contains the RID (uid) of our user
  unsigned long userInfoLevel = 3;
  unsigned char* userBuff = nullptr;
  unsigned long uid = -1;
  ret = NetUserGetInfo(nullptr, uname.data(), userInfoLevel, &userBuff);
  if (ret != NERR_Success && ret != NERR_UserNotFound) {
    return uid;
  }

  // SID belongs to a domain user, so we return the relative identifier (RID)
  if (ret == NERR_UserNotFound) {
    LPTSTR sidString;
    ConvertSidToStringSid(sid, &sidString);
    auto toks = osquery::split(sidString, "-");
    safeStrtoul(toks.at(toks.size() - 1), 10, uid);
    LocalFree(sidString);
  } else if (ret == NERR_Success) {
    uid = LPUSER_INFO_3(userBuff)->usri3_user_id;
  }

  NetApiBufferFree(userBuff);
  return uid;
}

int getGidFromSid(PSID sid) {
  auto eUse = SidTypeUnknown;
  unsigned long unameSize = 0;
  unsigned long domNameSize = 1;

  // LookupAccountSid first gets the size of the username buff required.
  LookupAccountSidW(
      nullptr, sid, nullptr, &unameSize, nullptr, &domNameSize, &eUse);
  std::vector<wchar_t> uname(unameSize);
  std::vector<wchar_t> domName(domNameSize);
  auto ret = LookupAccountSidW(nullptr,
                               sid,
                               uname.data(),
                               &unameSize,
                               domName.data(),
                               &domNameSize,
                               &eUse);

  if (ret == 0) {
    return -1;
  }
  // USER_INFO_3 struct contains the RID (uid) of our user
  unsigned long userInfoLevel = 3;
  unsigned char* userBuff = nullptr;
  unsigned long gid = -1;
  ret = NetUserGetInfo(nullptr, uname.data(), userInfoLevel, &userBuff);

  if (ret == NERR_UserNotFound) {
    LPTSTR sidString;
    ConvertSidToStringSid(sid, &sidString);
    auto toks = osquery::split(sidString, "-");
    safeStrtoul(toks.at(toks.size() - 1), 10, gid);
    LocalFree(sidString);
  } else if (ret == NERR_Success) {
    gid = LPUSER_INFO_3(userBuff)->usri3_primary_group_id;
  }

  NetApiBufferFree(userBuff);
  return gid;
}

std::unique_ptr<BYTE[]> getSidFromUsername(std::wstring accountName) {
  if (accountName.empty()) {
    LOG(INFO) << "No account name provided.";
    return nullptr;
  }

  // Call LookupAccountNameW() once to retrieve the necessary buffer sizes for
  // the SID (in bytes) and the domain name (in TCHARS):
  unsigned long sidBufferSize = 0;
  unsigned long domainNameSize = 0;
  auto eSidType = SidTypeUnknown;
  auto ret = LookupAccountNameW(nullptr,
                                accountName.c_str(),
                                nullptr,
                                &sidBufferSize,
                                nullptr,
                                &domainNameSize,
                                &eSidType);

  if (ret == 0 && GetLastError() != ERROR_INSUFFICIENT_BUFFER) {
    LOG(INFO) << "Failed to lookup accoun name "
              << wstringToString(accountName.c_str()) << " with "
              << GetLastError();
    return nullptr;
  }

  // Allocate buffers for the (binary data) SID and (wide string) domain name:
  auto sidBuffer = std::make_unique<BYTE[]>(sidBufferSize);
  std::vector<wchar_t> domainName(domainNameSize);

  // Call LookupAccountNameW() a second time to actually obtain the SID for the
  // given account name:
  ret = LookupAccountNameW(nullptr,
                           accountName.c_str(),
                           sidBuffer.get(),
                           &sidBufferSize,
                           domainName.data(),
                           &domainNameSize,
                           &eSidType);
  if (ret == 0) {
    LOG(INFO) << "Failed to lookup accoun name "
              << wstringToString(accountName.c_str()) << " with "
              << GetLastError();
    return nullptr;
  } else if (IsValidSid(sidBuffer.get()) == FALSE) {
    LOG(INFO) << "The SID for " << wstringToString(accountName.c_str())
              << " is invalid.";
  }

  // Implicit move operation. Caller "owns" returned pointer:
  return sidBuffer;
}

unsigned long getRidFromSid(PSID sid) {
  BYTE* countPtr = GetSidSubAuthorityCount(sid);
  unsigned long indexOfRid = static_cast<unsigned long>(*countPtr - 1);
  unsigned long* ridPtr = GetSidSubAuthority(sid, indexOfRid);
  return *ridPtr;
}

int platformGetUid() {
  auto token = INVALID_HANDLE_VALUE;
  if (!::OpenProcessToken(::GetCurrentProcess(), TOKEN_QUERY, &token)) {
    return -1;
  }

  unsigned long nbytes = 0;
  ::GetTokenInformation(token, TokenUser, nullptr, 0, &nbytes);
  if (nbytes == 0) {
    ::CloseHandle(token);
    return -1;
  }

  std::vector<char> tu_buffer;
  tu_buffer.assign(nbytes, '\0');

  auto status = ::GetTokenInformation(token,
                                      TokenUser,
                                      tu_buffer.data(),
                                      static_cast<DWORD>(tu_buffer.size()),
                                      &nbytes);
  ::CloseHandle(token);
  if (status == 0) {
    return -1;
  }

  auto tu = PTOKEN_USER(tu_buffer.data());
  return getUidFromSid(tu->User.Sid);
}

bool isLauncherProcessDead(PlatformProcess& launcher) {
  unsigned long code = 0;
  if (launcher.nativeHandle() == INVALID_HANDLE_VALUE) {
    return true;
  }

  if (!::GetExitCodeProcess(launcher.nativeHandle(), &code)) {
    LOG(WARNING) << "GetExitCodeProcess did not return a value, error code ("
                 << GetLastError() << ")";
    return false;
  }
  return (code != STILL_ACTIVE);
}

bool setEnvVar(const std::string& name, const std::string& value) {
  return (::SetEnvironmentVariableA(name.c_str(), value.c_str()) == TRUE);
}

bool unsetEnvVar(const std::string& name) {
  return (::SetEnvironmentVariableA(name.c_str(), nullptr) == TRUE);
}

boost::optional<std::string> getEnvVar(const std::string& name) {
  const auto kInitialBufferSize = 1024;
  std::vector<char> buf;
  buf.assign(kInitialBufferSize, '\0');

  auto value_len =
      ::GetEnvironmentVariableA(name.c_str(), buf.data(), kInitialBufferSize);
  if (value_len == 0) {
    return boost::none;
  }

  // It is always possible that between the first GetEnvironmentVariableA call
  // and this one, a change was made to our target environment variable that
  // altered the size. Currently, we ignore this scenario and fail if the
  // returned size is greater than what we expect.
  if (value_len > kInitialBufferSize) {
    buf.assign(value_len, '\0');
    value_len = ::GetEnvironmentVariableA(name.c_str(), buf.data(), value_len);
    if (value_len == 0 || value_len > buf.size()) {
      // The size returned is greater than the size we expected. Currently, we
      // will not deal with this scenario and just return as if an error has
      // occurred.
      return boost::none;
    }
  }

  return std::string(buf.data(), value_len);
}

ModuleHandle platformModuleOpen(const std::string& path) {
  return ::LoadLibraryA(path.c_str());
}

void* platformModuleGetSymbol(ModuleHandle module, const std::string& symbol) {
  return ::GetProcAddress(static_cast<HMODULE>(module), symbol.c_str());
}

std::string platformModuleGetError() {
  return std::string("GetLastError() = " + ::GetLastError());
}

bool platformModuleClose(ModuleHandle module) {
  return (::FreeLibrary(static_cast<HMODULE>(module)) != 0);
}

void setToBackgroundPriority() {}

// Helper function to determine if thread is running with admin privilege.
bool isUserAdmin() {
  HANDLE hToken = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &hToken)) {
    return false;
  }
  TOKEN_ELEVATION Elevation;
  DWORD cbSize = sizeof(TOKEN_ELEVATION);
  if (GetTokenInformation(
          hToken, TokenElevation, &Elevation, sizeof(Elevation), &cbSize) ==
      0) {
    CloseHandle(hToken);
    return false;
  }
  if (hToken != nullptr) {
    CloseHandle(hToken);
  }
  return Elevation.TokenIsElevated ? true : false;
}

int platformGetPid() {
  return static_cast<int>(GetCurrentProcessId());
}

int platformGetTid() {
  return static_cast<int>(GetCurrentThreadId());
}

void platformMainThreadExit(int excode) {
  ExitThread(excode);
}
}
