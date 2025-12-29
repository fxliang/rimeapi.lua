#include "utils.h"
#include "line_editor.h"

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
    size_t count = 0;
    {
      std::lock_guard<std::mutex> lock(noti_mutex);
      lua_queue = msg_queue;
      count = (msg_queue.size() < max_messages) ? msg_queue.size() : max_messages;
      std::vector<RimeNotificationMsg>().swap(msg_queue); // clear the queue
    }
    for (size_t i = 0; i < count; i++) {
      session_ids[i] = lua_queue[i].id;
      message_types[i] = lua_queue[i].type.c_str();
      message_values[i] = lua_queue[i].value.c_str();
    }
    return count;
  }

  RIME_API int init_bridge() {
    ensure_rime_api();
    rime_api->set_notification_handler(on_message, nullptr);
    FREE_RIME();
    return 0;
  }

  RIME_API void finalize_bridge() {
    ensure_rime_api();
    rime_api->set_notification_handler(nullptr, nullptr);
    FREE_RIME();
    std::vector<RimeNotificationMsg>().swap(lua_queue); // clear the lua queue
    std::lock_guard<std::mutex> lock(noti_mutex);
    std::vector<RimeNotificationMsg>().swap(msg_queue); // clear the queue
  }

  RIME_API const char* readline_bridge(const char* prompt) {
    static LineEditor editor(4096);
    static std::string line_buffer;
    if (editor.ReadLine(prompt, &line_buffer)) {
      return line_buffer.c_str();
    }
    return nullptr;
  }
}
