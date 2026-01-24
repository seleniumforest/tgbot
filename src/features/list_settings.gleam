import error.{type BotError}
import gleam/list
import gleam/result
import gleam/string
import helpers/log
import helpers/reply.{reply}
import models/bot_session.{type BotSession}
import telega/bot.{type Context}
import telega/update.{type Command}

pub fn command(
  ctx: Context(BotSession, BotError),
  _cmd: Command,
) -> Result(Context(BotSession, BotError), BotError) {
  let s = ctx.session.chat_settings
  let words = case s.banned_words |> list.is_empty {
    False -> s.banned_words |> string.join(", ")
    True -> "No banned words configured"
  }

  let msg =
    log.format(
      "Current settings:\n
/kickNewAccounts: {0}
/strictModeNonMembers: {1}
/checkChatClones : {2}
/checkFemaleName : {3}
/checkBannedWords: {4}
Banned words: {5}
",
      [
        s.kick_new_accounts |> string.inspect,
        s.strict_mode_nonmembers |> string.inspect,
        s.check_chat_clones |> string.inspect,
        s.check_female_name |> string.inspect,
        s.check_banned_words |> string.inspect,
        words,
      ],
    )

  reply(ctx, msg) |> result.try(fn(_) { Ok(ctx) })
}
