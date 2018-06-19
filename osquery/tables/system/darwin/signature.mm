/**
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under both the Apache 2.0 license (found in the
 *  LICENSE file in the root directory of this source tree) and the GPLv2 (found
 *  in the COPYING file in the root directory of this source tree).
 *  You may select, at your option, one of the above-listed licenses.
 */

#include <iomanip>
#include <sstream>

#include <CommonCrypto/CommonDigest.h>
#include <Foundation/Foundation.h>
#include <Security/CodeSigning.h>

#include <osquery/core.h>
#include <osquery/core/conversions.h>
#include <osquery/filesystem.h>
#include <osquery/logger.h>
#include <osquery/sql.h>
#include <osquery/tables.h>

#include "osquery/tables/system/darwin/keychain.h"

namespace osquery {
namespace tables {

// Empty string runs default verification on a file
std::set<std::string> kCheckedArches{"", "i386", "ppc", "arm", "x86_64"};

// Get the flags to pass to SecStaticCodeCheckValidityWithErrors, depending on
// the OS version.
Status getVerifyFlags(SecCSFlags& flags) {
  using boost::lexical_cast;
  using boost::bad_lexical_cast;

  static SecCSFlags sFlags;

  if (sFlags == 0) {
    auto qd = SQL::selectAllFrom("os_version");
    if (qd.size() != 1) {
      return Status(-1, "Couldn't determine OS X version");
    }

    int minorVersion;
    try {
      minorVersion = lexical_cast<int>(qd.front().at("minor"));
    } catch (const bad_lexical_cast& e) {
      return Status(-1, "Couldn't determine OS X version");
    }

    sFlags = kSecCSStrictValidate | kSecCSCheckAllArchitectures |
             kSecCSCheckNestedCode;
    if (minorVersion > 8) {
      sFlags |= kSecCSCheckNestedCode;
    }
  }

  flags = sFlags;
  return Status(0, "ok");
}

Status genSignatureForFileAndArch(const std::string& path,
                                  const std::string& arch,
                                  QueryData& results) {
  OSStatus result;
  SecStaticCodeRef static_code = nullptr;

  // Create a URL that points to this file.
  auto url = (__bridge CFURLRef)[NSURL fileURLWithPath:@(path.c_str())];
  if (url == nullptr) {
    return Status(1, "Could not create URL from file");
  }

  if (arch.empty()) {
    // Create the static code object.
    result = SecStaticCodeCreateWithPath(url, kSecCSDefaultFlags, &static_code);
    if (result != errSecSuccess) {
      if (static_code != nullptr) {
        CFRelease(static_code);
      }
      return Status(1, "Could not create static code object");
    }
  } else {
    CFMutableDictionaryRef context =
        CFDictionaryCreateMutable(nullptr,
                                  0,
                                  &kCFTypeDictionaryKeyCallBacks,
                                  &kCFTypeDictionaryValueCallBacks);
    auto cfkey = CFStringCreateWithCString(
        kCFAllocatorDefault, arch.c_str(), kCFStringEncodingUTF8);
    CFDictionaryAddValue(context, kSecCodeAttributeArchitecture, cfkey);
    CFRelease(cfkey);
    result = SecStaticCodeCreateWithPathAndAttributes(
        url, kSecCSDefaultFlags, context, &static_code);
    CFRelease(context);
    if (result != errSecSuccess) {
      if (static_code != nullptr) {
        CFRelease(static_code);
      }
      return Status(0, "No code to verify");
    }
  }

  Row r;
  r["path"] = path;
  r["arch"] = arch;
  r["identifier"] = "";

  SecCSFlags flags = 0;
  getVerifyFlags(flags);
  result = SecStaticCodeCheckValidityWithErrors(
      static_code, flags, nullptr, nullptr);
  if (result == errSecSuccess) {
    r["signed"] = "1";
  } else {
    // If this errors, then we either don't have a signature, or it's malformed.
    r["signed"] = "0";
  }

  CFDictionaryRef code_info = nullptr;
  result = SecCodeCopySigningInformation(
      static_code,
      kSecCSSigningInformation | kSecCSRequirementInformation,
      &code_info);

  if (result != errSecSuccess) {
    results.push_back(r);
    CFRelease(static_code);

    if (code_info != nullptr) {
      CFRelease(code_info);
    }
    return Status(1, "Could not get signing information for file");
  }

  // If we don't get an identifier for this file, then it's not signed.
  CFStringRef ident =
      (CFStringRef)CFDictionaryGetValue(code_info, kSecCodeInfoIdentifier);

  if (ident == nullptr) {
    results.push_back(r);
    CFRelease(code_info);
    CFRelease(static_code);
    return Status(1, "No identifier found for arch: " + arch);
  }

  r["identifier"] = stringFromCFString(ident);

  // Get CDHash
  r["cdhash"] = "";
  CFDataRef hashInfo =
      (CFDataRef)CFDictionaryGetValue(code_info, kSecCodeInfoUnique);
  if (hashInfo != nullptr) {
    // Get the SHA-1 bytes
    std::stringstream ss;
    auto bytes = CFDataGetBytePtr(hashInfo);
    if (bytes != nullptr &&
        CFDataGetLength(hashInfo) == CC_SHA1_DIGEST_LENGTH) {
      // Write bytes as hex strings
      for (size_t n = 0; n < CC_SHA1_DIGEST_LENGTH; n++) {
        ss << std::hex << std::setfill('0') << std::setw(2);
        ss << (unsigned int)bytes[n];
      }
      r["cdhash"] = ss.str();
    }
    if (r["cdhash"].length() != CC_SHA1_DIGEST_LENGTH * 2) {
      VLOG(1) << "Error extracting code directory hash";
      r["cdhash"] = "";
    }
  }

  // Team Identifier
  r["team_identifier"] = "";
  CFTypeRef team_ident = nullptr;
  if (CFDictionaryGetValueIfPresent(
          code_info, kSecCodeInfoTeamIdentifier, &team_ident)) {
    if (CFGetTypeID(team_ident) == CFStringGetTypeID()) {
      r["team_identifier"] = stringFromCFString((CFStringRef)team_ident);
    } else {
      VLOG(1) << "Team identifier was not a string";
    }
  }

  // Get common name
  r["authority"] = "";
  CFArrayRef certChain =
      (CFArrayRef)CFDictionaryGetValue(code_info, kSecCodeInfoCertificates);
  if (certChain != nullptr && CFArrayGetCount(certChain) > 0) {
    auto cert = SecCertificateRef(CFArrayGetValueAtIndex(certChain, 0));
    auto der_encoded_data = SecCertificateCopyData(cert);
    if (der_encoded_data != nullptr) {
      auto der_bytes = CFDataGetBytePtr(der_encoded_data);
      auto length = CFDataGetLength(der_encoded_data);
      auto x509_cert = d2i_X509(nullptr, &der_bytes, length);
      if (x509_cert != nullptr) {
        std::string subject;
        std::string issuer;
        std::string commonName;
        genCommonName(x509_cert, subject, commonName, issuer);
        r["authority"] = commonName;
        X509_free(x509_cert);
      } else {
        VLOG(1) << "Error decoding DER encoded certificate";
      }
      CFRelease(der_encoded_data);
    }
  }

  results.push_back(r);
  CFRelease(static_code);
  CFRelease(code_info);
  return Status(0);
}

// Generate a signature for a single file.
void genSignatureForFile(const std::string& path, QueryData& results) {
  for (const auto& arch : kCheckedArches) {
    // This returns a status but there is nothing we need to handle
    // here so we can safely ignore it
    genSignatureForFileAndArch(path, arch, results);
  }
}

QueryData genSignature(QueryContext& context) {
  QueryData results;

  // The query must provide a predicate with constraints including path or
  // directory. We search for the parsed predicate constraints with the equals
  // operator.
  auto paths = context.constraints["path"].getAll(EQUALS);
  context.expandConstraints(
      "path", LIKE, paths,
      ([&](const std::string& pattern, std::set<std::string>& out) {
        std::vector<std::string> patterns;
        auto status =
            resolveFilePattern(pattern, patterns, GLOB_ALL | GLOB_NO_CANON);
        if (status.ok()) {
          for (const auto& resolved : patterns) {
            out.insert(resolved);
          }
        }
        return status;
      }));
  @autoreleasepool {
    for (const auto& path_string : paths) {
      // Note: we are explicitly *not* using is_regular_file here, since you can
      // pass a directory path to the verification functions (e.g. for app
      // bundles, etc.)
      if (!pathExists(path_string).ok()) {
        continue;
      }
      genSignatureForFile(path_string, results);
    }
  }

  return results;
}
}
}
