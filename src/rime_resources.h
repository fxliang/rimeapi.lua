#pragma once

// Rime ownership and ABI policy. This layer intentionally has no Lua dependency.
#include "utils.h"
#include <memory>
#include <type_traits>
#include <unordered_map>
#include <unordered_set>

static std::unordered_set<RimeConfig*> cfg_borrowed_set;
static std::unordered_map<RimeConfig*, std::shared_ptr<void>> cfg_borrowed_owners;
static std::unordered_set<RimeSchemaList*> schemalist_borrowed_set;
static std::unordered_map<RimeSchemaList*, std::shared_ptr<void>> schemalist_borrowed_owners;
static std::mutex cfg_borrowed_mutex;
static std::mutex schemalist_borrowed_mutex;
static std::unordered_set<void*> levers_settings_owned;
static std::mutex levers_settings_mutex;

static inline bool is_config_borrowed(RimeConfig* cfg) {
  if (!cfg) return false;
  std::lock_guard<std::mutex> lock(cfg_borrowed_mutex);
  return cfg_borrowed_set.find(cfg) != cfg_borrowed_set.end();
}

static inline bool is_schemalist_borrowed(RimeSchemaList* list) {
  if (!list) return false;
  std::lock_guard<std::mutex> lock(schemalist_borrowed_mutex);
  return schemalist_borrowed_set.find(list) != schemalist_borrowed_set.end();
}

static inline void set_config_borrowed(
    RimeConfig* cfg, bool borrowed, std::shared_ptr<void> owner = {}) {
  if (!cfg) return;
  // Release retained owners outside the bookkeeping lock: deleters may reenter.
  std::shared_ptr<void> previous;
  {
    std::lock_guard<std::mutex> lock(cfg_borrowed_mutex);
    if (borrowed) {
      cfg_borrowed_set.insert(cfg);
      if (owner) {
        previous.swap(cfg_borrowed_owners[cfg]);
        cfg_borrowed_owners[cfg] = std::move(owner);
      }
    } else {
      cfg_borrowed_set.erase(cfg);
      auto it = cfg_borrowed_owners.find(cfg);
      if (it != cfg_borrowed_owners.end()) {
        previous = std::move(it->second);
        cfg_borrowed_owners.erase(it);
      }
    }
  }
}

static inline void set_schemalist_borrowed(
    RimeSchemaList* list, std::shared_ptr<void> owner = {}) {
  if (!list) return;
  std::shared_ptr<void> previous;
  {
    std::lock_guard<std::mutex> lock(schemalist_borrowed_mutex);
    schemalist_borrowed_set.insert(list);
    if (owner) {
      previous.swap(schemalist_borrowed_owners[list]);
      schemalist_borrowed_owners[list] = std::move(owner);
    }
  }
}

static inline void clear_schemalist_borrowed(RimeSchemaList* list) {
  if (!list) return;
  std::shared_ptr<void> previous;
  {
    std::lock_guard<std::mutex> lock(schemalist_borrowed_mutex);
    schemalist_borrowed_set.erase(list);
    auto it = schemalist_borrowed_owners.find(list);
    if (it != schemalist_borrowed_owners.end()) {
      previous = std::move(it->second);
      schemalist_borrowed_owners.erase(it);
    }
  }
}

static inline std::shared_ptr<void> get_schemalist_owner(RimeSchemaList* list) {
  if (!list) return {};
  std::lock_guard<std::mutex> lock(schemalist_borrowed_mutex);
  auto it = schemalist_borrowed_owners.find(list);
  return it == schemalist_borrowed_owners.end() ? std::shared_ptr<void>() : it->second;
}

static inline bool settings_has_borrowed_alias(void* owner) {
  if (!owner) return false;
  {
    std::lock_guard<std::mutex> lock(cfg_borrowed_mutex);
    for (const auto& entry : cfg_borrowed_owners)
      if (entry.second.get() == owner) return true;
  }
  {
    std::lock_guard<std::mutex> lock(schemalist_borrowed_mutex);
    for (const auto& entry : schemalist_borrowed_owners)
      if (entry.second.get() == owner) return true;
  }
  return false;
}

template<typename T>
struct RimeResourceDeleter {
  void operator()(T* value) const {
    if (!value) return;
    if constexpr (std::is_same_v<T, RimeConfig>) {
      if (!is_config_borrowed(value) && RIMEAPI && RIME_API_AVAILABLE(RIMEAPI, config_close))
        RIMEAPI->config_close(value);
      set_config_borrowed(value, false);
    } else if constexpr (std::is_same_v<T, RimeConfigIterator>) {
      if (RIMEAPI && RIME_API_AVAILABLE(RIMEAPI, config_end)) RIMEAPI->config_end(value);
    } else if constexpr (std::is_same_v<T, RimeStatus>) {
      if (RIMEAPI && RIME_API_AVAILABLE(RIMEAPI, free_status)) RIMEAPI->free_status(value);
    } else if constexpr (std::is_same_v<T, RimeContext>) {
      if (RIMEAPI && RIME_API_AVAILABLE(RIMEAPI, free_context)) RIMEAPI->free_context(value);
    } else if constexpr (std::is_same_v<T, RimeCommit>) {
      if (RIMEAPI && RIME_API_AVAILABLE(RIMEAPI, free_commit)) RIMEAPI->free_commit(value);
    } else if constexpr (std::is_same_v<T, RimeSchemaList>) {
      if (is_schemalist_borrowed(value)) {
        if (auto api = get_levers_api())
          if (RIME_LEVERS_API_AVAILABLE(api, schema_list_destroy)) api->schema_list_destroy(value);
      } else if (RIMEAPI && RIME_API_AVAILABLE(RIMEAPI, free_schema_list)) {
        RIMEAPI->free_schema_list(value);
      }
      clear_schemalist_borrowed(value);
    } else if constexpr (std::is_same_v<T, RimeCandidateListIterator>) {
      if (RIMEAPI && RIME_API_AVAILABLE(RIMEAPI, candidate_list_end)) RIMEAPI->candidate_list_end(value);
    } else if constexpr (std::is_same_v<T, RimeUserDictIterator>) {
      if (auto api = get_levers_api())
        if (RIME_LEVERS_API_AVAILABLE(api, user_dict_iterator_destroy)) api->user_dict_iterator_destroy(value);
    }
    delete value;
  }
};

template<typename T, typename = void>
struct has_rime_data_size : std::false_type {};

template<typename T>
struct has_rime_data_size<T, std::void_t<decltype(T::data_size)>> : std::true_type {};

template<typename T>
static std::shared_ptr<T> make_rime_resource() {
  std::shared_ptr<T> value(new T{}, RimeResourceDeleter<T>{});
  if constexpr (has_rime_data_size<T>::value)
    RIME_STRUCT_INIT(T, *value);
  return value;
}

static inline void destroy_levers_settings(void* ptr) {
  if (!ptr) return;
  bool owned;
  {
    std::lock_guard<std::mutex> lock(levers_settings_mutex);
    owned = levers_settings_owned.erase(ptr) != 0;
  }
  if (owned)
    if (auto api = get_levers_api())
      if (RIME_LEVERS_API_AVAILABLE(api, custom_settings_destroy))
        api->custom_settings_destroy(reinterpret_cast<RimeCustomSettings*>(ptr));
}

template<typename T>
static std::shared_ptr<T> adopt_levers_settings(T* ptr) {
  if (!ptr) return {};
  {
    std::lock_guard<std::mutex> lock(levers_settings_mutex);
    levers_settings_owned.insert(ptr);
  }
  return std::shared_ptr<T>(ptr, [](T* value) { destroy_levers_settings(value); });
}
