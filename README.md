# rimesync

I use [fcitx5-android + plugin.rime](https://github.com/fcitx5-android/fcitx5-android) as the input scheme on Android, and use [Syncthing-Fork](https://github.com/Catfriend1/syncthing-android) to synchronize the lexicon for rime on multiple devices.

However, Android's SAF policy prevents Syncthing-Fork from reading and writing to the fcitx5-android private directory. At the same time, fcitx5-android cannot synchronize rime's lexical library outside the fcitx5-android private directory, which directly leads to the inability to synchronize across devices.

So I wrote this little tool, which uses SAF to synchronize the rime lexicon in the fcitx5-android directory with a directory that Syncthing-Fork can read and write, so that you can eventually use Syncthing-Fork to synchronize the rime lexicon for multiple devices.

# How to use

1. Open the app and enter the installation_id configured by rime
2. Select the directory for rime synchronization, data/rime/sync in the fcitx5-android dedicated directory
3. Select a directory that can be read and written by the cross-device synchronization software for synchronization with data/rime/sync
4. Select the synchronization mode
5. Click the button in the lower right corner of the screen to start syncing data

Steps 1-4 will be recorded. Next time, just open the app and execute step 5.

There are three synchronization modes:
* **copy rime to remote**: Copy the installation_id directory in the directory selected in step 2 to the directory selected in step 3. Simply put, it pushes the local vocabulary out.
* **copy remote to rime**: Copy all the contents of the directory selected in step 3 to the directory in step 2. In simple terms, it replaces all local lexicons with those pulled from the remote lexicon.
* **sync**: First execute **copy rime to remote** and then execute **copy remote to rime**. However, when executing **copy remote to rime**, the installation_id directory will be ignored because this directory has just been rewritten to be exactly the same as in rime, so there is no need to copy the same thing back.

| Mode Name| When to use|
| --- | --- |
| copy rime to remote | Only want to share the vocabulary, but don't want to merge the remote vocabulary |
| copy remote to rime | Reinstalled fcitx5-android and needed to restore the dictionary using the same installation_id as before. |
| sync | Under normal circumstances, this mode is used for two-way vocabulary synchronization |

> The folder will be directly mkdir, and the files will be compared to see if they have changed before copying.