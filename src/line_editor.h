#pragma once

#include <cstddef>
#include <string>
#include <vector>

class LineEditor {
 public:
  explicit LineEditor(size_t max_length);

  // Reads one line into out; returns false on EOF or interruption.
  bool ReadLine(const char* prompt, std::string* out, const char* context = nullptr, const char* continuation_prompt = nullptr);
  void SetHistory(const std::vector<std::string>& history);

 private:
  int ReadChar();
  bool HandleEscapeSequence(int ch, std::string* line, size_t* cursor);
  void RecallHistory(int direction, std::string* line, size_t* cursor);
  void RefreshLine(const std::string& line, size_t cursor);
  void UpdateSuggestion(const std::string& line);
  
  // Helper to calculate row/col
  struct Pos { size_t row; size_t col; };
  Pos CalculatePos(const std::string& str, size_t index);

  std::string prompt_;
  std::string continuation_prompt_;
  std::string context_;
  std::string last_full_content_;
  size_t last_cursor_idx_ = 0;  bool IsPrintable(int ch) const;
  void EmitBell() const;

  size_t max_length_ = 0;
  std::vector<std::string> history_;
  size_t history_position_ = 0;
  bool browsing_history_ = false;
  std::string saved_line_;
  std::string suggestion_;
  size_t last_rendered_length_ = 0;
  size_t last_cursor_row_ = 0;
  size_t last_total_rows_ = 0;
  bool vt_supported_ = false;
};
