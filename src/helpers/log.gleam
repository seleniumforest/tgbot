import gleam/int
import gleam/io
import gleam/string

pub fn format(format: String, data: List(String)) -> String {
  format_loop(format, data, 0)
}

pub fn printf(format: String, data: List(String)) {
  format_loop(format, data, 0) |> io.println
}

pub fn print(format: String) {
  format_loop(format, [], 0) |> io.println
}

pub fn printf_err(format: String, data: List(String)) {
  format_loop(format, data, 0) |> io.println_error
}

pub fn print_err(format: String) {
  format_loop(format, [], 0) |> io.println_error
}

fn format_loop(format: String, data: List(String), depth: Int) -> String {
  case data {
    [] -> format
    [first, ..rest] ->
      format_loop(
        string.replace(format, "{" <> depth |> int.to_string <> "}", first),
        rest,
        depth + 1,
      )
  }
}
