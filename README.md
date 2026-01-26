# tgbot

A Telegram moderation bot written in Gleam (targeting the Erlang VM). The bot provides several moderation features for group chats: kicking new/unauthorized accounts, toggling strict mode for forwarded messages from linked channels, checking for chat clones, filtering by female names, and managing banned words.

This bot is still not a complete anti-spam solution, but can be used with other bots' captcha/anti-spam features. For now, it supposed to be an addition for existing anti-spam bots.  

This README explains how to set up Erlang and Gleam, build the project, run the bot, and lists the bot commands.

## Requirements

- Erlang/OTP (recommended: OTP 27+)
- Gleam (the Gleam compiler and toolchain)
- Git
- rebar3

## Install Erlang and Gleam

macOS (Homebrew)
```bash
brew install erlang
brew install gleam
```

Ubuntu / Debian (example)
```bash
# Install Erlang from package repositories or use asdf for more control
sudo apt update
sudo apt install -y curl build-essential

# Recommended: install Erlang via asdf or your preferred distribution
# Install Gleam (one of the options below)
```

Install Gleam via the official installer (works on macOS and Linux):
```bash
curl -sSL https://gleam.run/install.sh | sh
# Follow the script output to add Gleam to your PATH
```

Or install Gleam with asdf:
```bash
asdf plugin-add gleam https://github.com/gleam-lang/asdf-gleam.git
asdf install gleam latest
asdf global gleam latest
```

Verify installations:
```bash
erl -version    # Erlang/OTP version
gleam --version
```

## Clone and build

1. Clone the repository:
```bash
git clone https://github.com/seleniumforest/tgbot.git
cd tgbot
```

2. Build the project:
```bash
gleam build
```

- The Gleam tool will compile and produce BEAM artifacts under `_build/`. The build step will also fetch any Erlang dependencies via the standard toolchain.

## Configuration

The bot reads environment variables via a .env loader. At minimum you must provide your bot token.

Create a `.env` file in the project root (or export the variable into your shell):

.env:
```
BOT_TOKEN=123456:ABC-DEF...
```

Or export in your shell:
```bash
export BOT_TOKEN="123456:ABC-DEF..."
```

Notes:
- The code will attempt to load static resources from `./res/` (for example `res/female_names.txt` and `res/female_names_rus.txt`). Make sure the `res/` directory and those files are present in the repository; otherwise the bot will fail to start with an error like `Cannot load file: ./res/...`.
- Storage uses SQLite (via `sqlight`). A local SQLite DB will be created/managed automatically by the bot in the working directory (no separate DB server required).

## Running the bot

If your gleam installation provides `gleam run` you can run directly:

```bash
gleam run
```

If your environment requires using rebar3 directly (or you prefer to run a release), you can use the Erlang tooling (examples may vary by setup):

```bash
# Example: open an interactive shell with dependencies loaded (may vary per project)
rebar3 shell
# Then start the main function (if needed) or run according to your release setup.
```

The simplest approach is to use `gleam run` after setting `BOT_TOKEN` in the environment or adding `.env` with the token.

## Bot commands (for chat administrators)

The bot exposes the following administrative commands (use `/help` or `/start` in a private chat with the bot to get the help message):

- /kickNewAccounts [id_threshold]
  - Kick all users whose Telegram numeric id is greater than the provided threshold.
  - Example: `/kickNewAccounts 8000000000`
  - If no threshold is provided, command behavior will depend on context or current settings.

- /strictModeNonMembers
  - Toggle strict mode for forwarded messages from linked channels.
  - Strict mode enforces: no media, no links, no reactions, apply the current new-account id limit, and disallow empty usernames for forwarded messages.

- /checkChatClones
  - Toggle/check for accounts or channels whose name is similar to the chat title (attempt to detect clones).

- /checkFemaleName
  - Toggle the automatic check that kicks joining accounts whose name looks like an English or Russian female name (based on the `res/female_names*.txt` resource lists).

- /checkBannedWords
  - Toggle banning of messages that contain banned words. When enabled, messages containing banned words will be handled according to bot logic (ban/kick).

- /addBanWord <word1> [word2] ...
  - Add one or more words to the banned words list.
  - Example: `/addBanWord spam scam badword`

- /removeBanWord <word1> [word2] ...
  - Remove one or more words from the banned words list.
  - Example: `/removeBanWord badword`

- /listSettings
  - Show the current chat settings (which features are enabled, and the current list of banned words).

- /help or /start
  - Show the help message listing these commands.

Remarks:
- Command execution is gated by middleware that checks admin privileges for commands issued in groups; in private chats the bot will respond to commands from the chat user.
- Banned-words uses case-insensitive matching (words are stored lowercased).
- The bot spawns background checks for new members, strict mode, chat clone checks, female name checks, and banned word checks; these run asynchronously so commands that toggle behavior should take effect quickly.

## Resources

- Resource files used by the bot are in the `res/` directory. Ensure these are present:
  - `res/female_names.txt`
  - `res/female_names_rus.txt`

These lists are used by the female-name check feature.

## Troubleshooting

- "Cannot load file: ./res/...": Ensure the `res/` directory and required files exist and are readable.
- Bot shows errors about missing BOT_TOKEN: Ensure the `BOT_TOKEN` environment variable is defined or present in `.env`.
- If the bot fails to compile, check your Gleam and Erlang versions. Use Erlang/OTP 27+ and the latest stable Gleam for best compatibility.
- Check logs printed to stdout/stderr for details — the bot logs error traces when handlers fail.

## Contributing

If you'd like to contribute, please:
- Fork the repository
- Create a branch for your feature or fix
- Submit a PR with a clear description and tests/examples where appropriate

## License

```
            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
                    Version 2, December 2004

 Copyright (C) 2004 Sam Hocevar <sam@hocevar.net>

 Everyone is permitted to copy and distribute verbatim or modified
 copies of this license document, and changing it is allowed as long
 as the name is changed.

            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION

  0. You just DO WHAT THE FUCK YOU WANT TO.
```