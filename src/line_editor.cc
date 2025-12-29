#include "line_editor.h"

#include <cctype>
#ifdef _WIN32
#include <conio.h>
#include <windows.h>
#else
#include <termios.h>
#include <unistd.h>
#endif
#include <cstdio>
#include <algorithm>

#ifdef _WIN32
#ifndef ENABLE_VIRTUAL_TERMINAL_PROCESSING
#define ENABLE_VIRTUAL_TERMINAL_PROCESSING 0x0004
#endif
#endif

LineEditor::LineEditor(size_t max_length) : max_length_(max_length) {
#ifdef _WIN32
  HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
  if (hOut != INVALID_HANDLE_VALUE) {
    DWORD dwMode = 0;
    if (GetConsoleMode(hOut, &dwMode)) {
      dwMode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;
      if (SetConsoleMode(hOut, dwMode)) {
        vt_supported_ = true;
      }
    }
  }
#else
  vt_supported_ = true;
#endif
}

void LineEditor::SetHistory(const std::vector<std::string>& history) {
  history_ = history;
  history_position_ = history_.size();
}

bool LineEditor::ReadLine(const char* prompt, std::string* out, const char* context, const char* continuation_prompt) {
  if (!out)
    return false;
  prompt_ = prompt ? prompt : "";
  if (continuation_prompt) {
    continuation_prompt_ = continuation_prompt;
  } else {
    size_t last_non_space = prompt_.find_last_not_of(" ");
    if (last_non_space == std::string::npos) {
      continuation_prompt_ = prompt_;
    } else {
      std::string prefix = prompt_.substr(0, last_non_space + 1);
      std::string suffix = prompt_.substr(last_non_space + 1);
      continuation_prompt_ = prefix + prefix + suffix;
    }
  }
  context_ = context ? context : "";
#ifndef _WIN32
  struct TermiosGuard {
    termios original;
    bool active = false;
    TermiosGuard() {
      if (!isatty(STDIN_FILENO))
        return;
      if (tcgetattr(STDIN_FILENO, &original) == 0) {
        termios raw = original;
        raw.c_lflag &= ~(ICANON | ECHO);
        raw.c_cc[VMIN] = 1;
        raw.c_cc[VTIME] = 0;
        if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0) {
          active = true;
        }
      }
    }
    ~TermiosGuard() {
      if (active) {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original);
      }
    }
  } guard;
#endif
  std::string line;
  size_t cursor = 0;
  history_position_ = history_.size();
  browsing_history_ = false;
  saved_line_.clear();
  suggestion_.clear();
  last_full_content_.clear();
  last_cursor_idx_ = 0;
  
  // Initial suggestion update for context-based suggestions
  UpdateSuggestion(line);
  RefreshLine(line, cursor);
  
  while (true) {
    int ch = ReadChar();
    if (ch == -1) {
      putchar('\n');
      fflush(stdout);
      return false;
    }
    if (ch == '\r' || ch == '\n') {
      suggestion_.clear();
      RefreshLine(line, line.size());
      putchar('\n');
      fflush(stdout);
      *out = line;
      if (!out->empty()) {
        bool whitespace_only = true;
        for (char ch : *out) {
          if (!std::isspace(static_cast<unsigned char>(ch))) {
            whitespace_only = false;
            break;
          }
        }
        if (!whitespace_only) {
          const auto it = std::find(history_.begin(), history_.end(), *out);
          if (it == history_.end()) {
            history_.push_back(*out);
          }
          if (history_.size() > 4096) {
            history_.erase(history_.begin());
          }
        }
      }
      suggestion_.clear();
      last_rendered_length_ = 0;
      return true;
    }
    if ((ch == 4 || ch == 26) && line.empty()) {  // Ctrl-D / Ctrl-Z
      putchar('\n');
      fflush(stdout);
      return false;
    }
    if (ch == 3) {  // Ctrl-C
      putchar('\n');
      fflush(stdout);
      return false;
    }
    if (ch == 127 || ch == 8) {  // backspace
      if (cursor > 0) {
        line.erase(cursor - 1, 1);
        --cursor;
        UpdateSuggestion(line);
        RefreshLine(line, cursor);
      } else {
        EmitBell();
      }
      continue;
    }
    if (ch == 9) {  // Tab
      if (!suggestion_.empty()) {
        line.append(suggestion_);
        cursor = line.size();
        suggestion_.clear();
        RefreshLine(line, cursor);
      }
      continue;
    }
    if (HandleEscapeSequence(ch, &line, &cursor))
      continue;
    if (IsPrintable(ch)) {
      if (line.size() >= max_length_) {
        EmitBell();
        continue;
      }
      line.insert(cursor, 1, static_cast<char>(ch));
      ++cursor;
      UpdateSuggestion(line);
      RefreshLine(line, cursor);
      // editing after history recall should detach from history
      if (browsing_history_) {
        browsing_history_ = false;
        history_position_ = history_.size();
      }
      continue;
    }
    // ignore other keys
  }
}

int LineEditor::ReadChar() {
#ifdef _WIN32
  int ch = _getch();
  return ch;
#else
  unsigned char c = 0;
  ssize_t n = read(STDIN_FILENO, &c, 1);
  if (n <= 0)
    return -1;
  return static_cast<int>(c);
#endif
}

static std::string VisualTransform(const std::string& text, const std::string& continuation_prompt) {
  std::string visual = text;
  std::string replacement = "\n" + continuation_prompt;
  size_t pos = 0;
  while ((pos = visual.find('\n', pos)) != std::string::npos) {
    visual.replace(pos, 1, replacement);
    pos += replacement.length();
  }
  return visual;
}

static size_t LogicalToVisualIndex(const std::string& text, size_t index, size_t continuation_len) {
  size_t visual_index = 0;
  for (size_t i = 0; i < index && i < text.length(); ++i) {
    visual_index++;
    if (text[i] == '\n') {
      visual_index += continuation_len;
    }
  }
  return visual_index;
}

LineEditor::Pos LineEditor::CalculatePos(const std::string& str, size_t index) {
  Pos pos = {0, 0};
  for (size_t i = 0; i < index && i < str.length(); ++i) {
    if (str[i] == '\n') {
      pos.row++;
      pos.col = 0;
    } else {
      pos.col++;
    }
  }
  return pos;
}

void LineEditor::RefreshLine(const std::string& line, size_t cursor) {
  std::string visual_line = VisualTransform(line, continuation_prompt_);
  std::string visual_suggestion = VisualTransform(suggestion_, continuation_prompt_);

  if (vt_supported_) {
    // 1. Move cursor to the start of the previously rendered content
    Pos old_pos = CalculatePos(last_full_content_, last_cursor_idx_);
    if (old_pos.row > 0) {
      printf("\x1b[%zuA", old_pos.row);
    }
    putchar('\r');

    // 2. Clear everything from cursor down
    fputs("\x1b[0m", stdout);
    fputs("\x1b[J", stdout);

    // 3. Print new content
    fputs(prompt_.c_str(), stdout);
    fputs(visual_line.c_str(), stdout);
    if (!visual_suggestion.empty()) {
      fputs("\x1b[90m", stdout);
      fputs(visual_suggestion.c_str(), stdout);
      fputs("\x1b[0m", stdout);
    }
    std::string full_content = prompt_ + visual_line + visual_suggestion;

    // 4. Move cursor to the correct position
    size_t visual_cursor_offset = LogicalToVisualIndex(line, cursor, continuation_prompt_.length());
    size_t new_cursor_idx = prompt_.length() + visual_cursor_offset;
    
    // Safety clamp
    if (new_cursor_idx > full_content.length()) {
        new_cursor_idx = full_content.length();
    }

    Pos new_pos = CalculatePos(full_content, new_cursor_idx);
    Pos end_pos = CalculatePos(full_content, full_content.length());

    // Move up from end to target row
    if (end_pos.row > new_pos.row) {
      printf("\x1b[%zuA", end_pos.row - new_pos.row);
    }
    putchar('\r');
    if (new_pos.col > 0) {
      printf("\x1b[%zuC", new_pos.col);
    }

    fflush(stdout);

    last_full_content_ = full_content;
    last_cursor_idx_ = new_cursor_idx;
  } else {
#ifdef _WIN32
    // Fallback for Windows without VT
    putchar('\r');
    // Clear line by overwriting with spaces
    if (!last_full_content_.empty()) {
        size_t len = last_full_content_.length();
        for(size_t i=0; i<len+1; ++i) putchar(' ');
        putchar('\r');
    }

    fputs(prompt_.c_str(), stdout);
    fputs(visual_line.c_str(), stdout);
    if (!visual_suggestion.empty()) {
      HANDLE hConsole = GetStdHandle(STD_OUTPUT_HANDLE);
      CONSOLE_SCREEN_BUFFER_INFO consoleInfo;
      GetConsoleScreenBufferInfo(hConsole, &consoleInfo);
      WORD originalAttrs = consoleInfo.wAttributes;
      WORD bg = originalAttrs & (BACKGROUND_BLUE | BACKGROUND_GREEN |
                                 BACKGROUND_RED | BACKGROUND_INTENSITY);
      SetConsoleTextAttribute(hConsole, bg | FOREGROUND_INTENSITY);
      fputs(visual_suggestion.c_str(), stdout);
      SetConsoleTextAttribute(hConsole, originalAttrs);
    }
    
    last_full_content_ = prompt_ + visual_line + visual_suggestion;
    // Note: Cursor positioning is not handled perfectly here for mid-line edits without VT
#endif
  }
}
bool LineEditor::HandleEscapeSequence(int ch,
                                      std::string* line,
                                      size_t* cursor) {
  if (!line || !cursor)
    return false;
#ifdef _WIN32
  if (ch == 0 || ch == 224) {
    int next = _getch();
    switch (next) {
      case 72:  // up
        RecallHistory(-1, line, cursor);
        return true;
      case 80:  // down
        RecallHistory(1, line, cursor);
        return true;
      case 75:  // left
        if (*cursor > 0) {
          --(*cursor);
          RefreshLine(*line, *cursor);
        } else {
          EmitBell();
        }
        return true;
      case 77:  // right
        if (*cursor < line->size()) {
          ++(*cursor);
          RefreshLine(*line, *cursor);
        } else if (!suggestion_.empty()) {
          line->append(suggestion_);
          *cursor = line->size();
          suggestion_.clear();
          RefreshLine(*line, *cursor);
        } else {
          EmitBell();
        }
        return true;
      default:
        break;
    }
  }
#else
  if (ch == 27) {
    int next1 = ReadChar();
    if (next1 == -1)
      return true;
    if (next1 == '[') {
      int next2 = ReadChar();
      if (next2 == -1)
        return true;
      switch (next2) {
        case 'A':
          RecallHistory(-1, line, cursor);
          return true;
        case 'B':
          RecallHistory(1, line, cursor);
          return true;
        case 'C':
          if (*cursor < line->size()) {
            ++(*cursor);
            RefreshLine(*line, *cursor);
          } else if (!suggestion_.empty()) {
            line->append(suggestion_);
            *cursor = line->size();
            suggestion_.clear();
            RefreshLine(*line, *cursor);
          } else {
            EmitBell();
          }
          return true;
        case 'D':
          if (*cursor > 0) {
            --(*cursor);
            RefreshLine(*line, *cursor);
          } else {
            EmitBell();
          }
          return true;
        default:
          break;
      }
    }
    return true;
  }
#endif
  return false;
}

void LineEditor::RecallHistory(int direction,
                               std::string* line,
                               size_t* cursor) {
  if (history_.empty()) {
    EmitBell();
    return;
  }
  suggestion_.clear();
  if (!browsing_history_) {
    browsing_history_ = true;
    saved_line_ = *line;
    history_position_ = history_.size();
  }

  std::string search_prefix = context_ + saved_line_;

  size_t pos = history_position_;
  if (direction < 0) {
    while (pos > 0) {
      --pos;
      if (history_[pos].size() >= search_prefix.size() &&
          history_[pos].compare(0, search_prefix.size(), search_prefix) == 0) {
        history_position_ = pos;
        *line = history_[history_position_].substr(context_.length());
        *cursor = line->size();
        RefreshLine(*line, *cursor);
        return;
      }
    }
  } else {
    while (pos < history_.size()) {
      ++pos;
      if (pos == history_.size()) {
        *line = saved_line_;
        browsing_history_ = false;
        history_position_ = history_.size();
        *cursor = line->size();
        RefreshLine(*line, *cursor);
        return;
      }
      if (history_[pos].size() >= search_prefix.size() &&
          history_[pos].compare(0, search_prefix.size(), search_prefix) == 0) {
        history_position_ = pos;
        *line = history_[history_position_].substr(context_.length());
        *cursor = line->size();
        RefreshLine(*line, *cursor);
        return;
      }
    }
  }
  EmitBell();
}

void LineEditor::UpdateSuggestion(const std::string& line) {
  suggestion_.clear();
  // Allow suggestion even if line is empty, as long as we have context (previous lines)
  if (line.empty() && context_.empty()) {
    return;
  }
  
  std::string full_current = context_ + line;

  // Search history backwards for a match
  for (auto it = history_.rbegin(); it != history_.rend(); ++it) {
    if (it->length() > full_current.length() && it->substr(0, full_current.length()) == full_current) {
      suggestion_ = it->substr(full_current.length());
      return;
    }
  }
}

bool LineEditor::IsPrintable(int ch) const {
  if (ch < 0)
    return false;
  unsigned char uc = static_cast<unsigned char>(ch);
  return uc >= 32 && uc <= 126 && std::isprint(uc);
}

void LineEditor::EmitBell() const {
  putchar('\a');
  fflush(stdout);
}
