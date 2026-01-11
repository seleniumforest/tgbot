import error.{type BotError}
import models/bot_session.{type BotSession}
import telega/bot.{type Context}
import telega/reply
import telega/update.{type Command}

pub fn command(
  ctx: Context(BotSession, BotError),
  _cmd: Command,
) -> Result(Context(BotSession, BotError), BotError) {
  let msg =
    "Available commands:\n"
    <> "/kickNewAccounts [8000000000] - kick all users with telegram id over given.\n"
    <> "/removeCommentsNonMembers - remove all comments from linked channel's posts if user is not a chat member\n"
    <> "/help - show this message"

  let _ = reply.with_text(ctx, msg)
  Ok(ctx)
}
