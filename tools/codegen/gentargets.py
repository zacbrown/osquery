#!/usr/bin/env python

import argparse
import json
import logging
import os
import shutil

logging_format = '[%(levelname)s] %(message)s'
logging.basicConfig(level=logging.INFO, format=logging_format)

SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
REPO_ROOT_DIR = os.path.realpath(os.path.join(SCRIPT_DIR, "../.."))


def get_files_to_compile(json_data):
    files_to_compile = []
    for element in json_data:
        filename = element["file"]
        if not filename.endswith("tests.cpp") and \
                not filename.endswith("benchmarks.cpp") and \
                "third-party" not in filename and \
                "example" not in filename and \
                "generated/gen" not in filename and \
                "test_util" not in filename:
            base = filename.rfind("osquery/")
            filename = filename[base + len("osquery/"):]
            base_generated = filename.rfind("generated/")
            if base_generated >= 0:
                filename = filename[base_generated:]
            files_to_compile.append(filename)
    return files_to_compile

TARGETS_PREAMBLE = """
# DO NOT EDIT
# Automatically generated: make sync

thrift_library(
    name = "if",
    languages = [
        "cpp2",
        "py",
    ],
    py_base_module = "osquery",
    thrift_cpp2_options = "stack_arguments",
    thrift_srcs = {
        "extensions.thrift": [
            "Extension",
            "ExtensionManager",
        ],
    },
)

cpp_library(
    name="osquery_sdk",
    headers=AutoHeaders.RECURSIVE_GLOB,
    link_whole=True,
    srcs=[
"""

TARGETS_POSTSCRIPT = """  ],
    deps = [
        ":if-cpp2",
        "//folly/init:init",
        "//rocksdb:rocksdb",
        "//thrift/lib/cpp2:server",
        "//thrift/lib/cpp2:thrift_base",
    ],
    external_deps = [
        ("boost", None, "boost_filesystem"),
        ("boost", None, "boost_thread"),
        "boost",
        "glog",
        "gflags",
        ("googletest", None, "gtest"),
        ("util-linux", None, "uuid"),
        ("rapidjson"),
    ],
    compiler_flags = [
        "-Wno-unused-function",
        "-Wno-non-virtual-dtor",
        "-Wno-address",
        "-Wno-overloaded-virtual",
        "-Wno-unknown-pragmas",
    ],
    propagated_pp_flags = [
        "-DOSQUERY_BUILD_VERSION=%s-fb",
        "-DOSQUERY_BUILD_SDK_VERSION=%s-fb",
        "-DOSQUERY_BUILD_PLATFORM=centos7",
        "-DOSQUERY_BUILD_DISTRO=centos7",
        "-DOSQUERY_PLATFORM_MASK=9",
        "-DFBTHRIFT",
    ],
)
"""

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=(
        "Generate a TARGETS files from CMake metadata"
    ))
    parser.add_argument("--input", "-i", required=True)
    parser.add_argument("--version", "-v", required=True)
    parser.add_argument("--output", "-o", required=True)
    parser.add_argument("--sources", "-s", required=True)
    parser.add_argument("--sdk", required=True)
    args = parser.parse_args()

    try:
        with open(os.path.join(args.output, "TARGETS"), "w") as out:
            with open(args.input, "r") as f:
                try:
                    json_data = json.loads(f.read())
                except ValueError:
                    logging.critical("Error: %s is not valid JSON" % args.input)

                source_files = get_files_to_compile(json_data)
                out.write(TARGETS_PREAMBLE)
                for source_file in source_files:
                    if source_file == "extensions/impl_thrift.cpp":
                        source_file = "extensions/impl_fbthrift.cpp"
                    out.write("        \"%s\",\n" % source_file)
                    p = os.path.join(args.output, source_file)
                    if p.find("generated") < 0:
                        try:
                            os.makedirs(os.path.dirname(p), 0755)
                        except:
                            pass
                        shutil.copyfile(
                          os.path.join(args.sources, source_file), p)
                out.write(TARGETS_POSTSCRIPT % (args.version, args.sdk))

    except IOError as e:
        logging.critical("Error: %s doesn't exist: %s" % (args.input, str(e)))
