# NotifXUI - Monitor X-UI users🚀
check the status of users in all servers - Admin Assist with oneclick

NotifXUI is a powerful Telegram bot designed to help you monitor your X-UI users with ease. It allows you to add, delete, and list servers, as well as check the status of users (inbounds) on your panels. The bot supports multiple panel types, including **3x-ui** and **alireza0**, making it a versatile tool for X-UI administrators.

## 📦 Quick Installation

Get started with NotifXUI in just a few simple steps:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/yoyoraya/notifxui/master/install.sh)
```
## 🌟 Features
- **Server Management**: Add, delete, and list your X-UI servers effortlessly.

- **User Status Monitoring**: Check user statuses, including near expiry, low traffic, over traffic, and expired users.

- **Multi-Panel Support**: Works with both 3x-ui and alireza0 panel types.

- **Telegram Integration**: Manage your servers directly from Telegram with simple commands.

- **Automated Notifications**: Get real-time updates on user statuses and server activities.

## 🛠️ System Requirements
- **Python 3.x**: Ensure Python 3 is installed on your system.

- **pip**: Python package manager for installing dependencies.

- **Telegram Bot Token**: Obtain a token from BotFather.
##⚙️ Usage
#Commands
-/start: Start the bot and see the help message.

/connect address:port <username> <password> <panel_type>: Add a new server.
Example: /connect example.com:2053 admin password123 3x-ui

-/delete address:port: Delete a server.
Example: /delete example.com:2053

-/listservers: List all added servers.

-/notif: Check the status of users on your servers.
-/help: Show the help message.

## 👷‍♂️ Examples
Adding a Server
To add a server with the 3x-ui panel type:
```bash
/connect example.com:2053 admin password123
```
To add a server with the alireza0 panel type:

```bash
/connect example.com:2053 admin password123 alireza0
```
Deleting a Server
To delete a server:

```bash
/delete example.com:2053
```
## 🔐 Security Recommendations
-Use Strong Passwords: Ensure your server credentials are strong and unique.

-Limit Access: Only share the bot with trusted admins.

-Regular Updates: Keep your system and dependencies up to date.

Enjoy managing your X-UI panels with NotifXUI! 🤖

