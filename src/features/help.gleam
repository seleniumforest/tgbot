import error.{type BotError}
import helpers/reply.{reply}
import models/bot_session.{type BotSession}
import telega/bot.{type Context}
import telega/update.{type Command}

pub fn command(
  ctx: Context(BotSession, BotError),
  _cmd: Command,
) -> Result(Context(BotSession, BotError), BotError) {
  let msg =
    "Available commands:\n"
    <> "/kickNewAccounts [8000000000] - kick all users with telegram id over given.\n"
    <> "/strictModeNonMembers - strict mode (no media, links, reactions) for forwarded messages from linked channel\n"
    <> "/checkChatClones - bot will try to find accounts whose name is similar to chat title\n"
    <> "/checkFemaleName - bot will kick joining accounts with ENG/RU female name\n"
    <> "/help - show this message"

  let _ = reply(ctx, msg)
  Ok(ctx)
}
