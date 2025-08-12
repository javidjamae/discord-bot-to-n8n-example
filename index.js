// index.js
import { Client, GatewayIntentBits, Partials, Events, REST, Routes } from "discord.js";
import fetch from "node-fetch";
import { checkRequiredEnv } from "./env.js";

const {
  DISCORD_TOKEN,
  APPLICATION_ID,
  GUILD_ID,             // optional, for per-guild registration in the helper below
  N8N_WEBHOOK_URL,      // your n8n webhook that kicks off the workflow
  NODE_ENV
} = process.env;

// Ensure required environment variables are present
const missingEnv = checkRequiredEnv({ DISCORD_TOKEN, APPLICATION_ID, N8N_WEBHOOK_URL });
if (missingEnv.length) {
  console.error(`Missing required environment variable(s): ${missingEnv.join(", ")}`);
  process.exit(1);
}

// Optional one-time helper to register commands on startup if needed
async function registerCommands() {
  const rest = new REST({ version: "10" }).setToken(DISCORD_TOKEN);
  const commands = [
    { name: "generate-ideas", description: "Generate new content ideas", type: 1 },
    {
      name: "new-idea",
      description: "Create a new idea from a description",
      type: 1,
      options: [
        { name: "description", description: "Short summary of the idea", type: 3, required: true }
      ]
    }
  ];
  if (!GUILD_ID) {
    await rest.put(Routes.applicationCommands(APPLICATION_ID), { body: commands });
    console.log("Registered global commands");
  } else {
    await rest.put(Routes.applicationGuildCommands(APPLICATION_ID, GUILD_ID), { body: commands });
    console.log("Registered guild commands");
  }
}

const client = new Client({
  intents: [GatewayIntentBits.Guilds],
  partials: [Partials.Channel]
});

client.once(Events.ClientReady, async () => {
  console.log(`Logged in as ${client.user.tag}`);
  if (NODE_ENV === "register") {
    try { await registerCommands(); } catch (e) { console.error(e); }
  }
});

client.on(Events.InteractionCreate, async (interaction) => {
  if (!interaction.isChatInputCommand()) return;

  const command = interaction.commandName;
  const description = interaction.options.getString("description") || null;

  try {
    // Defer right away so you have time to run the workflow
    await interaction.deferReply({ ephemeral: false });

    // Kick off n8n with the context it needs
    const response = await fetch(N8N_WEBHOOK_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        command,
        description,
        guild_id: interaction.guildId,
        channel_id: interaction.channelId,
        user: {
          id: interaction.user.id,
          username: interaction.user.username,
          discriminator: interaction.user.discriminator
        },
        // Provide identifiers so n8n can post back via the bot API if you prefer
        response_hint: {
          application_id: APPLICATION_ID,
          interaction_token: null, // not needed for gateway path
          followup_target: {
            type: "channel",
            id: interaction.channelId
          },
          reply_message_id: null
        }
      })
    });

    if (!response.ok) {
      console.error(`Webhook request failed: ${response.status} ${response.statusText}`);
      await interaction.editReply("Sorry, something went wrong triggering the workflow.");
      return;
    }

    // Option A: let n8n post the final message using your Discord Bot API credential
    // For immediate feedback:
    await interaction.editReply("Got it. Generating ideas now... I will post them here.");

    // Option B: have n8n call back a lightweight status endpoint on the bot to deliver content,
    // then call interaction.editReply or followUp here. Most people use Option A.

  } catch (err) {
    console.error(err);
    if (interaction.deferred || interaction.replied) {
      await interaction.editReply("Sorry, something went wrong.");
    } else {
      await interaction.reply({ content: "Sorry, something went wrong.", ephemeral: true });
    }
  }
});

client.login(DISCORD_TOKEN);
