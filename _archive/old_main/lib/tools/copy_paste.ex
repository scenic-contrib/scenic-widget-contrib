defmodule QuillEx.Tools.CopyPaste do

    def paste do
    # def paste_aka_fetch_from_os_clipboard do
        {pastebin_text, 0} = System.cmd("pbpaste", [])
        pastebin_text
    end
end