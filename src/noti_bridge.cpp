#include "utils.h"
#include "line_editor.h"
#include <algorithm>

typedef struct {
  RimeSessionId id;
  std::string type;
  std::string value;
} RimeNotificationMsg;

static std::vector<RimeNotificationMsg> msg_queue;
static std::vector<RimeNotificationMsg> lua_queue;
static std::mutex noti_mutex;

static void on_message(void* context_object,
    RimeSessionId session_id,
    const char* msg_type,
    const char* msg_value) {
  const std::string type = std::string(msg_type ? msg_type : "");
  const std::string value = std::string(msg_value ? msg_value : "");
  {
    std::lock_guard<std::mutex> lock(noti_mutex);
    msg_queue.push_back({session_id, type, value});
  }
}

extern "C" {
  RIME_API size_t drain_notifications(
      RimeSessionId* session_ids,
      const char** message_types,
      const char** message_values,
      size_t max_messages) {
    if (max_messages == 0)
      return 0;
    std::lock_guard<std::mutex> lock(noti_mutex);
    const size_t count = std::min(msg_queue.size(), max_messages);
    lua_queue.assign(msg_queue.begin(), msg_queue.begin() + count);
    msg_queue.erase(msg_queue.begin(), msg_queue.begin() + count);
    for (size_t i = 0; i < count; i++) {
      session_ids[i] = lua_queue[i].id;
      message_types[i] = lua_queue[i].type.c_str();
      message_values[i] = lua_queue[i].value.c_str();
    }
    return count;
  }

  RIME_API int init_bridge() {
    if (!ensure_rime_api())
      return -1;
    std::lock_guard<std::mutex> lock(rime_api_mutex);
    if (!rime_api || !RIME_API_AVAILABLE(rime_api, set_notification_handler))
      return -1;
    rime_api->set_notification_handler(on_message, nullptr);
    return 0;
  }

  RIME_API void finalize_bridge() {
    {
      std::lock_guard<std::mutex> lock(rime_api_mutex);
      if (rime_api && RIME_API_AVAILABLE(rime_api, set_notification_handler))
        rime_api->set_notification_handler(nullptr, nullptr);
      rime_api = nullptr;
      FREE_RIME();
    }
    std::lock_guard<std::mutex> lock(noti_mutex);
    std::vector<RimeNotificationMsg>().swap(msg_queue);
  }

  RIME_API const char* readline_bridge(const char* prompt, const char** history, int history_count, const char* context, const char* continuation_prompt) {
    thread_local LineEditor editor(4096);
    if (history && history_count > 0) {
      std::vector<std::string> hist_vec;
      hist_vec.reserve(history_count);
      for (int i = 0; i < history_count; ++i) {
        if (history[i]) hist_vec.push_back(history[i]);
      }
      editor.SetHistory(hist_vec);
    }
    thread_local std::string line_buffer;
    if (editor.ReadLine(prompt, &line_buffer, context, continuation_prompt)) {
      return line_buffer.c_str();
    }
    return nullptr;
  }
}
