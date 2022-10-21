defmodule ScenicWidgets.TextPad.Structs.BufferTest do
    use ExUnit.Case
    alias ScenicWidgets.TextPad.Structs.Buffer

    #TODO introduce property tests here!

    test "make a new Buffer" do
        new_buf = Buffer.new(%{id: {:buffer, "luke_buf"}, type: :text})
        assert new_buf == %Buffer{
            id: {:buffer, "luke_buf"},
            name: "luke_buf",
            type: :text,
            data: nil,
            cursors: [%Buffer.Cursor{num: 1, line: 1, col: 1}],
            history: [],
            scroll_acc: {0, 0},
            read_only?: false
        }
    end

    # test "update the scroll_acc for a Buffer using a scroll delta" do
    #     new_buf = Buffer.new(%{id: {:buffer, "luke_buf"}})
    #     assert new_buf.scroll_acc == {0,0}

    #     %Buffer{} = second_new_buf = new_buf |> Buffer.update(%{scroll: {:delta, {5,5}}})
    #     assert second_new_buf.scroll_acc == {5,5}

    #     %Buffer{} = third_new_buf = second_new_buf |> Buffer.update(%{scroll: {:delta, {-5,0}}})
    #     assert third_new_buf.scroll_acc == {0,5}

    #     %Buffer{} = fourth_new_buf = third_new_buf |> Buffer.update(%{scroll: {:delta, {100, 100}}})
    #     assert fourth_new_buf.scroll_acc == {100,105}
    # end

    test "insert a buffer with some new data" do
        new_buf = Buffer.new(%{id: {:buffer, "luke_buf"}, type: :text})
        assert new_buf.data == nil

        result_buf = new_buf |> Buffer.update(%{data: "Remember that wherever your heart is, there you will find your treasure."})

        assert result_buf.data == "Remember that wherever your heart is, there you will find your treasure."
    end

    test "insert some text at a specific cursor point" do
        # https://www.gla.ac.uk/myglasgow/library/files/special/exhibns/month/april2009.html
        test_data = "The Rosarium philosophorum or Rosary of the philosophers is recognised as one of the most important texts of European alchemy.\nOriginally written in the 16th century, it is extensively quoted in later alchemical writings.\nIt first appeared in print as the second volume of a larger work entitled De alchimia opuscula complura veterum philosophorum, in Frankfurt in 1550.\nAs with many alchemical texts, its authorship is unknown.\nMany copies also circulated in manuscript, of which around thirty illustrated copies are extant.\nThere are six manuscript copies of it in our collection, including translations into French, German, and, in the case of this manuscript (Ms Ferguson 210), into English.\nThis latter is also supplied with 20 vividly coloured miniatures pasted in, which derive - with some alteration - from the original printed version."
        text_2_insert = "Alchemy eludes definition and is difficult to understand - "
        expected_final_data = "The Rosarium philosophorum or Rosary of the philosophers is recognised as one of the most important texts of European alchemy.\nOriginally written in the 16th century, " <> text_2_insert <> "it is extensively quoted in later alchemical writings.\nIt first appeared in print as the second volume of a larger work entitled De alchimia opuscula complura veterum philosophorum, in Frankfurt in 1550.\nAs with many alchemical texts, its authorship is unknown.\nMany copies also circulated in manuscript, of which around thirty illustrated copies are extant.\nThere are six manuscript copies of it in our collection, including translations into French, German, and, in the case of this manuscript (Ms Ferguson 210), into English.\nThis latter is also supplied with 20 vividly coloured miniatures pasted in, which derive - with some alteration - from the original printed version."

        test_buf =
            Buffer.new(%{id: {:buffer, "luke_buf"}, type: :text})
            |> Buffer.update(%{data: test_data})

        updated_buf = Buffer.update(test_buf, {:insert, text_2_insert, {:at_cursor, %Buffer.Cursor{line: 2, col: 41}}})

        assert updated_buf.data == expected_final_data
    end
    
end
  