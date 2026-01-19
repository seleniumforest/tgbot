import dot_env as dot
import dot_env/env
import error.{type BotError}
import features/check_chat_clones
import features/check_female_name
import features/help
import features/kick_new_accounts
import features/remove_comments_nonmembers
import gleam/bool
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import models/bot_session.{type BotSession, Resources}
import simplifile
import storage
import telega
import telega/api
import telega/bot.{type Context}
import telega/model/types.{GetChatAdministratorsParameters, Int}
import telega/polling
import telega/router
import telega/update.{type Update}

pub fn main() {
  dot.new()
  |> dot.load

  let db = storage.init()
  let resources = load_static_resources()

  let router =
    router.new("default")
    |> router.use_middleware(check_is_admin())
    |> router.use_middleware(inject_chat_settings(db))
    |> router.use_middleware(inject_static_resources(resources))
    |> router.use_middleware(extract_message_id())
    |> router.on_custom(fn(_) { True }, handle_update)
    |> router.on_command("kickNewAccounts", kick_new_accounts.command)
    |> router.on_command("checkChatClones", check_chat_clones.command)
    |> router.on_command("checkFemaleName", check_female_name.command)
    |> router.on_commands(["help", "start"], help.command)
    |> router.on_command(
      "removeCommentsNonMembers",
      remove_comments_nonmembers.command,
    )

  let assert Ok(token) = env.get_string("BOT_TOKEN")
  let assert Ok(bot) =
    telega.new_for_polling(token:)
    |> telega.with_router(router)
    |> telega.with_session_settings(
      bot.SessionSettings(
        persist_session: fn(_key, session) { Ok(session) },
        get_session: fn(_key) { bot_session.default(db) |> option.Some |> Ok },
        default_session: fn() { bot_session.default(db) },
      ),
    )
    |> telega.init_for_polling()

  let assert Ok(poller) =
    polling.start_polling_with_offset(
      bot,
      -1,
      timeout: 20,
      limit: 100,
      allowed_updates: [],
      poll_interval: 1000,
    )

  polling.wait_finish(poller)
}

fn inject_static_resources(resources: bot_session.Resources) {
  fn(handler) {
    fn(ctx: bot.Context(BotSession, BotError), update: update.Update) {
      let session = bot_session.BotSession(..ctx.session, resources:)
      let modified_ctx = bot.Context(..ctx, session:)
      handler(modified_ctx, update)
    }
  }
}

fn load_static_resources() {
  let names = load_lines("./res/female_names.txt")
  let names_rus = load_lines("./res/female_names_rus.txt")

  Resources(
    female_names: names
    |> list.append(names_rus)
    |> list.map(fn(x) { string.lowercase(x) }),
  )
}

fn load_lines(path: String) {
  let lines = simplifile.read(path)
  case lines {
    Error(e) -> {
      let msg =
        "Cannot load file: " <> path <> " Error: " <> e |> string.inspect
      panic as msg
    }
    Ok(content) -> {
      content
      |> string.split("\n")
      |> list.filter(fn(x) { string.length(x) > 0 })
    }
  }
}

fn handle_update(
  ctx: Context(BotSession, BotError),
  upd: Update,
) -> Result(Context(BotSession, BotError), BotError) {
  process.spawn_unlinked(fn() {
    use ctx, upd <- kick_new_accounts.checker(ctx, upd)
    use ctx, upd <- remove_comments_nonmembers.checker(ctx, upd)
    use ctx, upd <- check_chat_clones.checker(ctx, upd)
    use _ctx, _upd <- check_female_name.checker(ctx, upd)
    Nil
  })
  Ok(ctx)
}

fn check_is_admin() {
  fn(handler) {
    fn(ctx: bot.Context(BotSession, BotError), upd: update.Update) {
      case upd {
        update.CommandUpdate(message:, ..) -> {
          use <- bool.guard(
            message.chat.type_ |> option.unwrap("") == "private",
            handler(ctx, upd),
          )

          let is_admin =
            api.get_chat_administrators(
              ctx.config.api_client,
              GetChatAdministratorsParameters(Int(upd.chat_id)),
            )
            |> result.unwrap([])
            |> list.find(fn(el) {
              case el {
                types.ChatMemberAdministratorChatMember(admin) ->
                  admin.user.id == upd.from_id
                types.ChatMemberOwnerChatMember(owner) ->
                  owner.user.id == upd.from_id
                _ -> False
              }
            })

          case is_admin |> result.is_ok {
            False -> Ok(ctx)
            True -> handler(ctx, upd)
          }
        }
        _ -> handler(ctx, upd)
      }
    }
  }
}

fn inject_chat_settings(db) {
  fn(handler) {
    fn(ctx: bot.Context(BotSession, BotError), update: update.Update) {
      let chat =
        result.try_recover(storage.get_chat(db, ctx.update.chat_id), fn(err) {
          case err {
            storage.EmptyDataError -> {
              io.println(
                "Creating chat settings for new key "
                <> ctx.update.chat_id |> int.to_string,
              )
              storage.create_chat(db, ctx.update.chat_id)
            }
            _ -> Error(err)
          }
        })

      case chat {
        Error(e) -> {
          io.println_error(
            "ERROR: Could not get chat settings for chat "
            <> ctx.key
            <> " error: "
            <> e |> string.inspect
            <> " Processing with default handler. This is NOT normal behaviour",
          )
          handler(ctx, update)
        }
        Ok(chat_settings) -> {
          let session =
            bot_session.BotSession(..ctx.session, chat_settings:, db:)
          let modified_ctx = bot.Context(..ctx, session:)
          handler(modified_ctx, update)
        }
      }
    }
  }
}

fn extract_message_id() {
  fn(handler) {
    fn(ctx: bot.Context(BotSession, BotError), update: update.Update) {
      let message_id: option.Option(Int) = case update {
        update.AudioUpdate(message:, ..)
        | update.BusinessMessageUpdate(message:, ..)
        | update.CommandUpdate(message:, ..)
        | update.EditedBusinessMessageUpdate(message:, ..)
        | update.EditedMessageUpdate(message:, ..)
        | update.MessageUpdate(message:, ..)
        | update.PhotoUpdate(message:, ..)
        | update.TextUpdate(message:, ..)
        | update.VideoUpdate(message:, ..)
        | update.VoiceUpdate(message:, ..)
        | update.WebAppUpdate(message:, ..) -> option.Some(message.message_id)
        update.ChannelPostUpdate(post:, ..) -> option.Some(post.message_id)
        update.MessageReactionUpdate(message_reaction_updated:, ..) ->
          option.Some(message_reaction_updated.message_id)
        _ -> option.None
      }

      let session = bot_session.BotSession(..ctx.session, message_id:)
      let modified_ctx = bot.Context(..ctx, session:)
      handler(modified_ctx, update)
    }
  }
}
