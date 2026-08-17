defmodule QuillEx.Structs.BufferTest do
    use ExUnit.Case
    alias QuillEx.Structs.Buffer

    test "make a new Buffer" do
        new_buf = Buffer.new(%{id: {:buffer, "luke_buf"}})
        assert new_buf == %QuillEx.Structs.Buffer{
            id: {:buffer, "luke_buf"},
            name: "luke_buf",
            type: :text,
            data: "",
            cursors: [%QuillEx.Structs.Buffer.Cursor{num: 1, line: 1, col: 1}],
            history: [],
            scroll_acc: {0, 0},
            read_only?: false
        }
    end

end
 

# defmodule ScenicWidgets.TextPad.Structs.Buffer2Test do
#     use ExUnit.Case
#     alias ScenicWidgets.TextPad.Structs.Buffer

#     #TODO introduce property tests here!

#     test "make a new Buffer" do
#         new_buf = Buffer.new(%{id: {:buffer, "luke_buf"}, type: :text})
#         assert new_buf == %Buffer{
#             id: {:buffer, "luke_buf"},
#             name: "luke_buf",
#             type: :text,
#             data: nil,
#             cursors: [%Buffer.Cursor{num: 1, line: 1, col: 1}],
#             history: [],
#             scroll_acc: {0, 0},
#             read_only?: false
#         }
#     end

#     # test "update the scroll_acc for a Buffer using a scroll delta" do
#     #     new_buf = Buffer.new(%{id: {:buffer, "luke_buf"}})
#     #     assert new_buf.scroll_acc == {0,0}

#     #     %Buffer{} = second_new_buf = new_buf |> Buffer.update(%{scroll: {:delta, {5,5}}})
#     #     assert second_new_buf.scroll_acc == {5,5}

#     #     %Buffer{} = third_new_buf = second_new_buf |> Buffer.update(%{scroll: {:delta, {-5,0}}})
#     #     assert third_new_buf.scroll_acc == {0,5}

#     #     %Buffer{} = fourth_new_buf = third_new_buf |> Buffer.update(%{scroll: {:delta, {100, 100}}})
#     #     assert fourth_new_buf.scroll_acc == {100,105}
#     # end

#     test "insert a buffer with some new data" do
#         new_buf = Buffer.new(%{id: {:buffer, "luke_buf"}, type: :text})
#         assert new_buf.data == nil

#         result_buf = new_buf |> Buffer.update(%{data: "Remember that wherever your heart is, there you will find your treasure."})

#         assert result_buf.data == "Remember that wherever your heart is, there you will find your treasure."
#     end

#     test "insert some text at a specific cursor point" do
#         # https://www.gla.ac.uk/myglasgow/library/files/special/exhibns/month/april2009.html
#         test_data = "The Rosarium philosophorum or Rosary of the philosophers is recognised as one of the most important texts of European alchemy.\nOriginally written in the 16th century, it is extensively quoted in later alchemical writings.\nIt first appeared in print as the second volume of a larger work entitled De alchimia opuscula complura veterum philosophorum, in Frankfurt in 1550.\nAs with many alchemical texts, its authorship is unknown.\nMany copies also circulated in manuscript, of which around thirty illustrated copies are extant.\nThere are six manuscript copies of it in our collection, including translations into French, German, and, in the case of this manuscript (Ms Ferguson 210), into English.\nThis latter is also supplied with 20 vividly coloured miniatures pasted in, which derive - with some alteration - from the original printed version."
#         text_2_insert = "Alchemy eludes definition and is difficult to understand - "
#         expected_final_data = "The Rosarium philosophorum or Rosary of the philosophers is recognised as one of the most important texts of European alchemy.\nOriginally written in the 16th century, " <> text_2_insert <> "it is extensively quoted in later alchemical writings.\nIt first appeared in print as the second volume of a larger work entitled De alchimia opuscula complura veterum philosophorum, in Frankfurt in 1550.\nAs with many alchemical texts, its authorship is unknown.\nMany copies also circulated in manuscript, of which around thirty illustrated copies are extant.\nThere are six manuscript copies of it in our collection, including translations into French, German, and, in the case of this manuscript (Ms Ferguson 210), into English.\nThis latter is also supplied with 20 vividly coloured miniatures pasted in, which derive - with some alteration - from the original printed version."

#         test_buf =
#             Buffer.new(%{id: {:buffer, "luke_buf"}, type: :text})
#             |> Buffer.update(%{data: test_data})

#         updated_buf = Buffer.update(test_buf, {:insert, text_2_insert, {:at_cursor, %Buffer.Cursor{line: 2, col: 41}}})

#         assert updated_buf.data == expected_final_data
#     end
    
# end
  








# defmodule ScenicWidgets.TextPad.Structs.BufferTest do
#     use ExUnit.Case
#     alias ScenicWidgets.TextPad.Structs.Buffer

#     #TODO introduce property tests here!

#     test "make a new Buffer" do
#         new_buf = Buffer.new(%{id: {:buffer, "luke_buf"}, type: :text})
#         assert new_buf == %Buffer{
#             id: {:buffer, "luke_buf"},
#             name: "luke_buf",
#             type: :text,
#             data: nil,
#             cursors: [%Buffer.Cursor{num: 1, line: 1, col: 1}],
#             history: [],
#             scroll_acc: {0, 0},
#             read_only?: false
#         }
#     end

#     # test "update the scroll_acc for a Buffer using a scroll delta" do
#     #     new_buf = Buffer.new(%{id: {:buffer, "luke_buf"}})
#     #     assert new_buf.scroll_acc == {0,0}

#     #     %Buffer{} = second_new_buf = new_buf |> Buffer.update(%{scroll: {:delta, {5,5}}})
#     #     assert second_new_buf.scroll_acc == {5,5}

#     #     %Buffer{} = third_new_buf = second_new_buf |> Buffer.update(%{scroll: {:delta, {-5,0}}})
#     #     assert third_new_buf.scroll_acc == {0,5}

#     #     %Buffer{} = fourth_new_buf = third_new_buf |> Buffer.update(%{scroll: {:delta, {100, 100}}})
#     #     assert fourth_new_buf.scroll_acc == {100,105}
#     # end

#     test "insert a buffer with some new data" do
#         new_buf = Buffer.new(%{id: {:buffer, "luke_buf"}, type: :text})
#         assert new_buf.data == nil

#         result_buf = new_buf |> Buffer.update(%{data: "Remember that wherever your heart is, there you will find your treasure."})

#         assert result_buf.data == "Remember that wherever your heart is, there you will find your treasure."
#     end

#     test "insert some text at a specific cursor point" do
#         # https://www.gla.ac.uk/myglasgow/library/files/special/exhibns/month/april2009.html
#         test_data = "The Rosarium philosophorum or Rosary of the philosophers is recognised as one of the most important texts of European alchemy.\nOriginally written in the 16th century, it is extensively quoted in later alchemical writings.\nIt first appeared in print as the second volume of a larger work entitled De alchimia opuscula complura veterum philosophorum, in Frankfurt in 1550.\nAs with many alchemical texts, its authorship is unknown.\nMany copies also circulated in manuscript, of which around thirty illustrated copies are extant.\nThere are six manuscript copies of it in our collection, including translations into French, German, and, in the case of this manuscript (Ms Ferguson 210), into English.\nThis latter is also supplied with 20 vividly coloured miniatures pasted in, which derive - with some alteration - from the original printed version."
#         text_2_insert = "Alchemy eludes definition and is difficult to understand - "
#         expected_final_data = "The Rosarium philosophorum or Rosary of the philosophers is recognised as one of the most important texts of European alchemy.\nOriginally written in the 16th century, " <> text_2_insert <> "it is extensively quoted in later alchemical writings.\nIt first appeared in print as the second volume of a larger work entitled De alchimia opuscula complura veterum philosophorum, in Frankfurt in 1550.\nAs with many alchemical texts, its authorship is unknown.\nMany copies also circulated in manuscript, of which around thirty illustrated copies are extant.\nThere are six manuscript copies of it in our collection, including translations into French, German, and, in the case of this manuscript (Ms Ferguson 210), into English.\nThis latter is also supplied with 20 vividly coloured miniatures pasted in, which derive - with some alteration - from the original printed version."

#         test_buf =
#             Buffer.new(%{id: {:buffer, "luke_buf"}, type: :text})
#             |> Buffer.update(%{data: test_data})

#         updated_buf = Buffer.update(test_buf, {:insert, text_2_insert, {:at_cursor, %Buffer.Cursor{line: 2, col: 41}}})

#         assert updated_buf.data == expected_final_data
#     end
    
# end
  












# defmodule Flamelex.Test.Buffer.Utils.TextBuffer.ModifyHelperTest do
#     use ExUnit.Case
#     alias Flamelex.Buffer.Utils.TextBuffer.ModifyHelper
  
  
#       # sourced from: https://vim.fandom.com/wiki/Vim_buffer_FAQ
#       @sentence_a "A buffer is a file loaded into memory for editing.\n"
#       @sentence_b "All opened files are associated with a buffer.\n"
#       @sentence_c "There are also buffers not associated with any file.\n"
  
  
#     test "inserting text into a buffer, by specifying the overall character position to insert it" do
#       buffer_state = %{data: @sentence_a <> @sentence_b <> @sentence_c}
#       modification = {:insert, "Luke is the best!", String.length(@sentence_a)}
  
#       {:ok, modified_buffer} = ModifyHelper.modify(buffer_state, modification)
  
#       assert modified_buffer.data == @sentence_a <> "Luke is the best!" <> @sentence_b <> @sentence_c
#       assert Enum.count(modified_buffer.lines) == 3 # NOTE: I never added any newline in my Modification
#       assert modified_buffer.unsaved_changes? == true
#       assert modified_buffer.lines == [
#         %{line: 1, text: @sentence_a |> String.trim()},
#         %{line: 2, text: "Luke is the best!" <> @sentence_b |> String.trim()},
#         %{line: 3, text: @sentence_c |> String.trim()}
#       ]
#     end
  
#     # test "insert some text onto a line"
  
#     describe "with standard test buffer" do
#       setup [:standard_test_buffer]
  
#       test "append a new line (insert under the current line)", %{buffer_state: buffer_state} do
#         assert Enum.count(buffer_state.lines) == 3
  
#         modification =  %{append: "\n", line: 1} # appent to line 1, means, we expect line 2 to be a blank new line
#         {:ok, modified_buffer} = ModifyHelper.modify(buffer_state, modification)
  
#         assert Enum.count(modified_buffer.lines) == 4
#         assert modified_buffer.unsaved_changes? == true
#         assert modified_buffer.data == @sentence_a <> "\n" <> @sentence_b <> @sentence_c
#         assert modified_buffer.lines == [
#           %{line: 1, text: @sentence_a |> String.trim()},
#           %{line: 2, text: ""},
#           %{line: 3, text: @sentence_b |> String.trim()},
#           %{line: 4, text: @sentence_c |> String.trim()}
#         ]
#       end
#     end
  
  
#     test "insert some text into a buffer based on the cursor coordinates" do
#       buffer_state = %{
#         data: %{data: @sentence_a <> @sentence_b <> @sentence_c},
#         lines: [ #NOTE: we trim there here, because, lines aren't supposed to contain newline chars
#           %{line: 1, text: @sentence_a |> String.trim()},
#           %{line: 2, text: @sentence_b |> String.trim()},
#           %{line: 3, text: @sentence_c |> String.trim()},
#         ],
#         cursors: [
#           # place the cursor a few words into the text
#           %{col: String.length("All opened files"), line: 2} #TODO edge cases - what if the cursor is on the end of a line? the start of a line? the middle of a line? does the cursor position mean, on the cursor position, or after it?
#         ],
#         unsaved_changes?: false
#       }
#       modification = {:insert, " are freee!! And never,", %{coords: {:cursor, 1}}}
  
#       {:ok, modified_buffer} = ModifyHelper.modify(buffer_state, modification)
#       assert Enum.count(modified_buffer.lines) == 3 # NOTE: I never added any newline in my Modification
#       assert modified_buffer.unsaved_changes? == true
#       assert modified_buffer.lines == [
#         %{line: 1, text: @sentence_a |> String.trim()},
#         %{line: 2, text: "All opened files are freee!! And never, are associated with a buffer.\n" |> String.trim()},
#         %{line: 3, text: @sentence_c |> String.trim()}
#       ]
#     end
  
  
#     defp standard_test_buffer(context) do
#       buffer_state = %{
#         data: @sentence_a <> @sentence_b <> @sentence_c,
#         lines: [ #NOTE: we trim there here, because, lines aren't supposed to contain newline chars
#           %{line: 1, text: @sentence_a |> String.trim()},
#           %{line: 2, text: @sentence_b |> String.trim()},
#           %{line: 3, text: @sentence_c |> String.trim()},
#         ],
#         cursors: [%{line: 1, col: 1}],
#         unsaved_changes?: false
#       }
  
#       context |> Map.merge(%{buffer_state: buffer_state})
#     end
#   end
  









# defmodule QuillEx.Structs.BufferTest do
#     use ExUnit.Case
#     alias QuillEx.Structs.Buffer

#     test "make a new Buffer" do
#         new_buf = Buffer.new(%{id: {:buffer, "luke_buf"}})
#         assert new_buf == %QuillEx.Structs.Buffer{
#             id: {:buffer, "luke_buf"},
#             name: "luke_buf",
#             data: nil,
#             details: nil,
#             cursors: [%QuillEx.Structs.Buffer.Cursor{num: 1, line: 1, col: 1}],
#             history: [],
#             scroll_acc: {0, 0},
#             read_only?: false
#         }
#     end

#     # test "update the scroll_acc for a Buffer using a scroll delta" do
#     #     new_buf = Buffer.new(%{id: {:buffer, "luke_buf"}})
#     #     assert new_buf.scroll_acc == {0,0}

#     #     %Buffer{} = second_new_buf = new_buf |> Buffer.update(%{scroll: {:delta, {5,5}}})
#     #     assert second_new_buf.scroll_acc == {5,5}

#     #     %Buffer{} = third_new_buf = second_new_buf |> Buffer.update(%{scroll: {:delta, {-5,0}}})
#     #     assert third_new_buf.scroll_acc == {0,5}

#     #     %Buffer{} = fourth_new_buf = third_new_buf |> Buffer.update(%{scroll: {:delta, {100, 100}}})
#     #     assert fourth_new_buf.scroll_acc == {100,105}
#     # end

#     test "insert a buffer with some new data" do
#         new_buf = Buffer.new(%{id: {:buffer, "luke_buf"}})
#         assert new_buf.data == nil

#         result_buf = new_buf |> Buffer.update(%{data: "Remember that wherever your heart is, there you will find your treasure."})

#         assert result_buf.data == "Remember that wherever your heart is, there you will find your treasure."
#     end

#     test "insert some text at a specific cursor point" do
#         # https://www.gla.ac.uk/myglasgow/library/files/special/exhibns/month/april2009.html
#         test_data = "The Rosarium philosophorum or Rosary of the philosophers is recognised as one of the most important texts of European alchemy.\nOriginally written in the 16th century, it is extensively quoted in later alchemical writings.\nIt first appeared in print as the second volume of a larger work entitled De alchimia opuscula complura veterum philosophorum, in Frankfurt in 1550.\nAs with many alchemical texts, its authorship is unknown.\nMany copies also circulated in manuscript, of which around thirty illustrated copies are extant.\nThere are six manuscript copies of it in our collection, including translations into French, German, and, in the case of this manuscript (Ms Ferguson 210), into English.\nThis latter is also supplied with 20 vividly coloured miniatures pasted in, which derive - with some alteration - from the original printed version."
#         text_2_insert = "Alchemy eludes definition and is difficult to understand - "
#         expected_final_data = "The Rosarium philosophorum or Rosary of the philosophers is recognised as one of the most important texts of European alchemy.\nOriginally written in the 16th century, " <> text_2_insert <> "it is extensively quoted in later alchemical writings.\nIt first appeared in print as the second volume of a larger work entitled De alchimia opuscula complura veterum philosophorum, in Frankfurt in 1550.\nAs with many alchemical texts, its authorship is unknown.\nMany copies also circulated in manuscript, of which around thirty illustrated copies are extant.\nThere are six manuscript copies of it in our collection, including translations into French, German, and, in the case of this manuscript (Ms Ferguson 210), into English.\nThis latter is also supplied with 20 vividly coloured miniatures pasted in, which derive - with some alteration - from the original printed version."

#         test_buf =
#             Buffer.new(%{id: {:buffer, "luke_buf"}})
#             |> Buffer.update(%{data: test_data})

#         updated_buf = Buffer.update(test_buf, {:insert, text_2_insert, {:at_cursor, %Buffer.Cursor{line: 2, col: 41}}})

#         assert updated_buf.data == expected_final_data
#     end
    
# end
  