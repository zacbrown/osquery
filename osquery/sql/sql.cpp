/**
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under both the Apache 2.0 license (found in the
 *  LICENSE file in the root directory of this source tree) and the GPLv2 (found
 *  in the COPYING file in the root directory of this source tree).
 *  You may select, at your option, one of the above-listed licenses.
 */

#include <sstream>

#include <osquery/core.h>
#include <osquery/logger.h>
#include <osquery/registry.h>
#include <osquery/sql.h>
#include <osquery/tables.h>

#include "osquery/core/conversions.h"

namespace osquery {

FLAG(int32, value_max, 512, "Maximum returned row value size");

CREATE_LAZY_REGISTRY(SQLPlugin, "sql");

SQL::SQL(const std::string& query, bool use_cache) {
  TableColumns table_columns;
  status_ = getQueryColumns(query, table_columns);
  if (status_.ok()) {
    for (auto c : table_columns) {
      columns_.push_back(std::get<0>(c));
    }
    status_ = osquery::query(query, results_, use_cache);
  }
}

const QueryData& SQL::rows() const {
  return results_;
}

QueryData& SQL::rows() {
  return results_;
}

const ColumnNames& SQL::columns() const {
  return columns_;
}

bool SQL::ok() const {
  return status_.ok();
}

const Status& SQL::getStatus() const {
  return status_;
}

std::string SQL::getMessageString() const {
  return status_.toString();
}

static inline void escapeNonPrintableBytes(std::string& data) {
  std::string escaped;
  // clang-format off
  char const hex_chars[16] = {
    '0', '1', '2', '3', '4', '5', '6', '7',
    '8', '9', 'A', 'B', 'C', 'D', 'E', 'F',
  };
  // clang-format on

  bool needs_replacement = false;
  for (size_t i = 0; i < data.length(); i++) {
    if (((unsigned char)data[i]) < 0x20 || ((unsigned char)data[i]) >= 0x80) {
      needs_replacement = true;
      escaped += "\\x";
      escaped += hex_chars[(((unsigned char)data[i])) >> 4];
      escaped += hex_chars[((unsigned char)data[i] & 0x0F) >> 0];
    } else {
      escaped += data[i];
    }
  }

  // Only replace if any escapes were made.
  if (needs_replacement) {
    data = std::move(escaped);
  }
}

void escapeNonPrintableBytesEx(std::string& data) {
  return escapeNonPrintableBytes(data);
}

void SQL::escapeResults() {
  for (auto& row : results_) {
    for (auto& column : row) {
      escapeNonPrintableBytes(column.second);
    }
  }
}

QueryData SQL::selectAllFrom(const std::string& table) {
  PluginResponse response;
  Registry::call("table", table, {{"action", "generate"}}, response);
  return response;
}

QueryData SQL::selectAllFrom(const std::string& table,
                             const std::string& column,
                             ConstraintOperator op,
                             const std::string& expr) {
  PluginRequest request = {{"action", "generate"}};
  {
    // Create a fake content, there will be no caching.
    QueryContext ctx;
    ctx.constraints[column].add(Constraint(op, expr));
    TablePlugin::setRequestFromContext(ctx, request);
  }

  PluginResponse response;
  Registry::call("table", table, request, response);
  return response;
}

QueryData SQL::selectFrom(const std::initializer_list<std::string>& columns,
                          const std::string& table,
                          const std::string& column,
                          ConstraintOperator op,
                          const std::string& expr) {
  PluginRequest request = {{"action", "generate"}};
  {
    // Create a fake content, there will be no caching.
    QueryContext ctx;
    ctx.constraints[column].add(Constraint(op, expr));
    ctx.colsUsed = UsedColumns(columns);
    TablePlugin::setRequestFromContext(ctx, request);
  }

  PluginResponse response;
  Registry::call("table", table, request, response);
  return response;
}

Status SQLPlugin::call(const PluginRequest& request, PluginResponse& response) {
  response.clear();
  if (request.count("action") == 0) {
    return Status(1, "SQL plugin must include a request action");
  }

  if (request.at("action") == "query") {
    bool use_cache = (request.count("cache") && request.at("cache") == "1");
    return this->query(request.at("query"), response, use_cache);
  } else if (request.at("action") == "columns") {
    TableColumns columns;
    auto status = this->getQueryColumns(request.at("query"), columns);
    // Convert columns to response
    for (const auto& column : columns) {
      response.push_back(
          {{"n", std::get<0>(column)},
           {"t", columnTypeName(std::get<1>(column))},
           {"o", INTEGER(static_cast<size_t>(std::get<2>(column)))}});
    }
    return status;
  } else if (request.at("action") == "attach") {
    // Attach a virtual table name using an optional included definition.
    return this->attach(request.at("table"));
  } else if (request.at("action") == "detach") {
    this->detach(request.at("table"));
    return Status(0, "OK");
  } else if (request.at("action") == "tables") {
    std::vector<std::string> tables;
    auto status = this->getQueryTables(request.at("query"), tables);
    if (status.ok()) {
      for (const auto& table : tables) {
        response.push_back({{"t", table}});
      }
    }
    return status;
  }
  return Status(1, "Unknown action");
}

Status query(const std::string& q, QueryData& results, bool use_cache) {
  return Registry::call(
      "sql",
      "sql",
      {{"action", "query"}, {"cache", (use_cache) ? "1" : "0"}, {"query", q}},
      results);
}

Status getQueryColumns(const std::string& q, TableColumns& columns) {
  PluginResponse response;
  auto status = Registry::call(
      "sql", "sql", {{"action", "columns"}, {"query", q}}, response);

  // Convert response to columns
  for (const auto& item : response) {
    columns.push_back(make_tuple(
        item.at("n"), columnTypeName(item.at("t")), ColumnOptions::DEFAULT));
  }
  return status;
}

Status mockGetQueryTables(std::string copy_q,
                          std::vector<std::string>& tables) {
  std::transform(copy_q.begin(), copy_q.end(), copy_q.begin(), ::tolower);
  auto offset_from = copy_q.find("from ");
  if (offset_from == std::string::npos) {
    return Status(1);
  }

  auto simple_tables = osquery::split(copy_q.substr(offset_from + 5), ",");
  for (const auto& table : simple_tables) {
    tables.push_back(table);
  }
  return Status(0);
}

Status getQueryTables(const std::string& q, std::vector<std::string>& tables) {
  if (!Registry::get().exists("sql", "sql") && kToolType == ToolType::TEST) {
    // We 'mock' this functionality for internal tests.
    return mockGetQueryTables(q, tables);
  }

  PluginResponse response;
  auto status = Registry::call(
      "sql", "sql", {{"action", "tables"}, {"query", q}}, response);

  for (const auto& table : response) {
    tables.push_back(table.at("t"));
  }
  return status;
}
}
