IMPORT os
IMPORT util

CONSTANT LOREM_IPSUM
    = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Dolor sed viverra ipsum nunc aliquet bibendum enim. In massa tempor nec feugiat. Nunc aliquet bibendum enim facilisis gravida. Nisl nunc mi ipsum faucibus vitae aliquet nec ullamcorper. Amet luctus venenatis lectus magna fringilla. Volutpat maecenas volutpat blandit aliquam etiam erat velit scelerisque in. Egestas egestas fringilla phasellus faucibus scelerisque eleifend. Sagittis orci a scelerisque purus semper eget duis. Nulla pharetra diam sit amet nisl suscipit. Sed adipiscing diam donec adipiscing tristique risus nec feugiat in. Fusce ut placerat orci nulla. Pharetra vel turpis nunc eget lorem dolor. Tristique senectus et netus et malesuada.  Etiam tempor orci eu lobortis elementum nibh tellus molestie. Neque egestas congue quisque egestas. Egestas integer eget aliquet nibh praesent tristique. Vulputate mi sit amet mauris. Sodales neque sodales ut etiam sit. Dignissim suspendisse in est ante in. Volutpat commodo sed egestas egestas. Felis donec et odio pellentesque diam. Pharetra vel turpis nunc eget lorem dolor sed viverra. Porta nibh venenatis cras sed felis eget. Aliquam ultrices sagittis orci a. Dignissim diam quis enim lobortis. Aliquet porttitor lacus luctus accumsan. Dignissim convallis aenean et tortor at risus viverra adipiscing at."

CONSTANT MAX_ROWS = 25

TYPE fields_type DYNAMIC ARRAY OF RECORD
    name STRING,
    type STRING,
    default DYNAMIC ARRAY OF STRING
END RECORD

DEFINE field_list RECORD
    input fields_type,
    arrays DYNAMIC ARRAY OF RECORD
        scr STRING,
        ia fields_type
    END RECORD
END RECORD

DEFINE word_list DYNAMIC ARRAY OF STRING

MAIN
    DEFINE d ui.Dialog
    DEFINE ev STRING
    DEFINE table_idx, field_idx, row_idx INTEGER
    DEFINE form_name STRING

    CALL init_wordlist()
    OPTIONS FIELD ORDER FORM
    OPTIONS INPUT WRAP

    LABEL lbl_beginning:

    -- Pass .42f in argument 1
    LET form_name = base.Application.getArgument(1)
    -- If no argument, then select file
    IF form_name IS NULL THEN
        CALL ui.Interface.frontCall(
            "standard", "openfile", ["", "Form Files", "*.42f", "Form Fields"],
            form_name)
        LET form_name = os.Path.rootName(form_name)
    END IF
    -- No form then exit
    IF form_name IS NULL THEN
        EXIT PROGRAM 1
    END IF

    OPEN WINDOW w WITH FORM form_name
        ATTRIBUTES(TEXT = SFMT("Dialog Preview %1",
            os.Path.baseName(form_name)))

    CALL populate_field_list(SFMT("%1.42f", form_name))

    LET d = ui.Dialog.createMultipleDialog()
    -- add global triggers
    CALL d.addTrigger("ON ACTION accept")
    CALL d.addTrigger("ON ACTION cancel")
    CALL d.addTrigger("ON ACTION close")

    -- Add dialogs
    IF field_list.input.getLength() > 0 THEN
        CALL d.addInputByName(field_list.input, "input")
        #CALL d.addConstructByName(field_list.input, "input")  TODO add a means to differentiate input, construct
    END IF

    FOR table_idx = 1 TO field_list.arrays.getLength()
        #CALL d.addDisplayArrayTo(field_list.arrays[table_idx].ia, field_list.arrays[table_idx].scr) TODO add a means to differentiate
        CALL d.addInputArrayFrom(
            field_list.arrays[table_idx].ia, field_list.arrays[table_idx].scr)
    END FOR

    -- Set initial values
    FOR field_idx = 1 TO field_list.input.getLength()
        CALL d.setFieldValue(
            field_list.input[field_idx].name,
            field_list.input[field_idx].default[1])
    END FOR

    FOR table_idx = 1 TO field_list.arrays.getLength()
        FOR row_idx = 1 TO MAX_ROWS
            CALL d.setCurrentRow(field_list.arrays[table_idx].scr, row_idx)
            FOR field_idx = 1 TO field_list.arrays[table_idx].ia.getLength()
                CALL d.setFieldValue(
                    field_list.arrays[table_idx].ia[field_idx].name,
                    field_list.arrays[table_idx].ia[field_idx].default[row_idx])
            END FOR
            CALL d.setCurrentRow(field_list.arrays[table_idx].scr, 1)
        END FOR
    END FOR

    MESSAGE "Close Window to Exit"

    WHILE (ev := d.nextEvent()) IS NOT NULL
        CASE ev
            WHEN "ON ACTION accept"
                CALL d.accept()
                EXIT WHILE
            WHEN "ON ACTION cancel"
                CALL d.cancel()
                EXIT WHILE
            WHEN "ON ACTION close"
                EXIT PROGRAM
        END CASE
    END WHILE

    -- initialise and begin again
    CALL d.close()
    CLOSE WINDOW w
    INITIALIZE field_list.* TO NULL
    GOTO lbl_beginning
END MAIN

FUNCTION populate_field_list(form_name)
    DEFINE form_name STRING
    DEFINE doc om.DomDocument

    DEFINE form_field_list, table_column_list, table_list om.NodeList
    DEFINE root_node, field_node, table_node om.DomNode

    DEFINE table_idx, field_idx, row_idx INTEGER
    DEFINE table_column_count INTEGER

    LET doc = om.DomDocument.createFromXmlFile(form_name)
    LET root_node = doc.getDocumentElement()
    #DISPLAY root_node.toString()

    -- Add any FormFields to INPUT

    LET form_field_list = root_node.selectByTagName("FormField")
    FOR field_idx = 1 TO form_field_list.getLength()
        LET field_node = form_field_list.item(field_idx)

        LET field_list.input[field_idx].name =
            field_node.getAttribute("colName")
        LET field_list.input[field_idx].type =
            NVL(field_node.getAttribute("sqlType"), "STRING")
        -- If CHAR and not CHAR(n) then defaults to CHAR(1) which is not useful.  Infer n from width
        IF field_list.input[field_idx].type MATCHES "*CHAR" THEN
            LET field_list.input[field_idx].type =
                SFMT("%1(%2)",
                    field_list.input[field_idx].type,
                    field_node.getFirstChild().getAttribute("width"))
        END IF
        LET field_list.input[field_idx].default[1] =
            generate_default_value(field_node)

    END FOR

    LET table_list = root_node.selectByTagName("Table")
    FOR table_idx = 1 TO table_list.getLength()
        LET table_node = table_list.item(table_idx)
        LET field_list.arrays[table_idx].scr =
            table_node.getAttribute("tabName")
        LET table_column_list = table_node.selectByTagName("TableColumn")
        FOR field_idx = 1 TO table_column_list.getLength()
            LET field_node = table_column_list.item(field_idx)
            LET field_list.arrays[table_idx].ia[field_idx].name =
                field_node.getAttribute("colName")
            LET field_list.arrays[table_idx].ia[field_idx].type =
                NVL(field_node.getAttribute("sqlType"), "STRING")
            FOR row_idx = 1 TO MAX_ROWS
                LET field_list.arrays[table_idx].ia[field_idx]
                        .default[row_idx] =
                    generate_default_value(field_node)
            END FOR
        END FOR

        -- add in phantom columns
        LET table_column_count = table_column_list.getLength()
        LET table_column_list = table_node.selectByTagName("PhantomColumn")
        FOR field_idx = 1 TO table_column_list.getLength()
            LET field_node = table_column_list.item(field_idx)
            LET field_list.arrays[table_idx] .ia[table_column_count + field_idx]
                    .name =
                field_node.getAttribute("colName")
            LET field_list.arrays[table_idx] .ia[table_column_count + field_idx]
                    .type =
                NVL(field_node.getAttribute("sqlType"), "STRING")
            FOR row_idx = 1 TO MAX_ROWS
                LET field_list.arrays[table_idx]
                        .ia[table_column_count + field_idx].default[row_idx] =
                    ""
            END FOR
        END FOR
    END FOR
END FUNCTION

PRIVATE FUNCTION generate_default_value(field_node)
    DEFINE field_node om.DomNode
    DEFINE data_type, widget_type STRING

    -- Calculate based on sqlType or widget type if defined
    LET data_type = field_node.getAttribute("sqlType")
    LET widget_type = field_node.getFirstChild().getTagName()
    CASE
        WHEN widget_type = "TextEdit"
            RETURN LOREM_IPSUM

        WHEN widget_type = "Image"
            RETURN IIF(util.Math.rand(2) == 0, "smiley", "ssmiley")

        WHEN widget_type = "CheckBox"
            RETURN generate_checkbox(field_node)

        WHEN widget_type = "Slider" OR widget_type = "ProgressBar"
            OR widget_type = "SpinEdit"
            RETURN generate_slider_progressbar_spinedit(field_node)

        WHEN widget_type = "ComboBox" OR widget_type = "RadioGroup"
            RETURN generate_combobox_radiogroup(field_node)

        WHEN data_type = "DATE" OR widget_type = "DateEdit"
            RETURN generate_date(field_node)

        WHEN data_type MATCHES "DATETIME*" OR widget_type = "DateTimeEdit"
            OR widget_type = "TimeEdit"
            RETURN generate_datetime(field_node)

        WHEN data_type = "INTEGER" OR data_type = "SMALLINT"
            OR data_type MATCHES "DECIMAL*"
            OR data_type MATCHES "FLOAT*" -- TODO add other type
            RETURN generate_number(field_node)

        WHEN data_type = "STRING" OR data_type MATCHES "CHAR*"
            OR data_type MATCHES "VARCHAR*"
            RETURN generate_string(field_node)
        OTHERWISE
            RETURN generate_string(field_node)
    END CASE
END FUNCTION

-- TODO add randomness
PRIVATE FUNCTION generate_string(field_node om.DomNode)
    DEFINE child_node om.DomNode
    DEFINE string1, string2 STRING
    DEFINE char CHAR(10)
    DEFINE width INTEGER
    DEFINE i INTEGER

    LET child_node = field_node.getFirstChild()

    IF child_node.getTagName() = "TextEdit" THEN
        RETURN LOREM_IPSUM
    END IF
    LET width = child_node.getAttribute("width")

    IF width > 10 AND child_node.getTagName() <> "ButtonEdit"
        THEN -- Make it two words, its probably a name or desc
        LET string1 = word_list[util.Math.rand(word_list.getLength()) + 1]
        LET string1 =
            string1.subString(1, 1).toUpperCase(),
            string1.subString(2, string1.getLength())
        LET string2 = word_list[util.Math.rand(word_list.getLength()) + 1]
        LET string2 =
            string2.subString(1, 1).toUpperCase(),
            string2.subString(2, string2.getLength())
        RETURN SFMT("%1 %2", string1, string2)
    END IF

    -- Make it an upper case code, AAA0000000
    IF width > 3 THEN
        FOR i = 1 TO 3
            LET char[i] = ASCII (util.Math.rand(26) + 65)
        END FOR
        FOR i = 4 TO width
            LET char[i] = ASCII (util.Math.rand(10) + 48)
            IF i >= 10 THEN
                EXIT FOR
            END IF
        END FOR
        RETURN char CLIPPED
    END IF

    -- Make it alpha code e.g. AAA
    FOR i = 1 TO width
        LET char[i] = ASCII (util.Math.rand(26) + 65)
    END FOR

    RETURN char CLIPPED
END FUNCTION

PRIVATE FUNCTION generate_number(field_node om.DomNode)
    DEFINE child_node om.DomNode
    DEFINE type STRING
    DEFINE format STRING

    DEFINE precision, scale SMALLINT
    DEFINE result STRING

    DEFINE decimal_point, start_point, end_point INTEGER

    LET child_node = field_node.getFirstChild()
    LET type = field_node.getAttribute("sqlType") -- DECIMAL(,2)
    LET format = child_node.getAttribute("format") -- USING "###,##&.&&"
    LET format =
        string_replace(format, "&amp;", "&") -- 42f is xml  so replace html char
    LET format = string_replace(format, ",", "") -- don't count , in space

    -- Default in case nothing gets found
    LET precision = 5
    LET scale = 2

    CASE
        WHEN format.getLength() > 0 -- Use format if specified
            LET decimal_point = format.getIndexOf(".", 1)
            IF decimal_point = 0 THEN
                LET precision = format.getLength()
            ELSE
                LET precision = decimal_point - 1
            END IF
            IF format.getCharAt(1) = "-" THEN
                LET precision = precision - 1
            END IF
            LET end_point = format.getIndexOf("\"", decimal_point)
            LET scale = format.subString(decimal_point + 1, end_point - 1)
            LET precision = precision + scale

        WHEN type MATCHES "DECIMAL(*"
            LET start_point = type.getIndexOf("(", 1)
            LET decimal_point = type.getIndexOf(",", start_point)
            IF decimal_point > 0 THEN
                LET end_point = type.getIndexOf(")", decimal_point)
                LET precision =
                    type.subString(start_point + 1, decimal_point - 1)
                LET scale = type.subString(decimal_point + 1, end_point - 1)
            ELSE
                LET end_point = type.getIndexOf(")", start_point)
                LET precision = type.subString(start_point + 1, end_point - 1)
                LET scale = 0
            END IF

        OTHERWISE
            LET precision = child_node.getAttribute("width")

            IF type MATCHES "*INT*" THEN
                LET scale = 0
            ELSE
                LET scale = 2
            END IF

            IF type = "BIGINT" AND precision > 18 THEN
                LET precision = 18
            END IF
            IF type = "INTEGER" AND precision > 9 THEN
                LET precision = 9
            END IF
            IF type = "SMALLINT" AND precision > 4 THEN
                LET precision = 4
            END IF
            IF type = "TINYINT" AND precision > 2 THEN
                LET precision = 2
            END IF
    END CASE

    -- rand can only take an integer
    IF precision > 9 THEN
        LET precision = 9
    END IF

    LET result =
        util.Math.rand(util.Math.pow(10, precision)) / util.Math.pow(10, scale)

    RETURN result
END FUNCTION

PRIVATE FUNCTION string_replace(s STRING, old STRING, new STRING) RETURNS STRING
    DEFINE sb base.StringBuffer
    LET sb = base.StringBuffer.create()
    CALL sb.append(s)
    CALL sb.replace(old, new, 0)
    RETURN sb.toString()
END FUNCTION

PRIVATE FUNCTION extract_decimal(d STRING) RETURNS(SMALLINT, SMALLINT)
    DEFINE left, comma, right SMALLINT

    LET left = d.getIndexof("(", 1)
    IF left = 0 THEN
        RETURN 16, 0
    END IF
    LET comma = d.getIndexOf(".", left)
    IF comma = 0 THEN
        RETURN d.subString(left + 1, d.getLength() - 1), 0
    END IF
    LET right = d.getIndexOf(")", left)
    RETURN d.subString(left + 1, comma - 1), d.subString(comma + 1, right - 1)
END FUNCTION

PRIVATE FUNCTION generate_date(field_node om.DomNode)
    RETURN MDY(util.Math.rand(12) + 1, util.Math.rand(28) + 1, YEAR(TODAY))
END FUNCTION

PRIVATE FUNCTION generate_datetime(field_node om.DomNode)
    RETURN CURRENT YEAR TO SECOND #FRACTION(5)
END FUNCTION

PRIVATE FUNCTION generate_time(field_node om.DomNode)
    RETURN CURRENT HOUR TO FRACTION(5)
END FUNCTION

PRIVATE FUNCTION generate_slider_progressbar_spinedit(field_node om.DomNode)
    DEFINE child_node om.DomNode
    DEFINE valuemin, valuemax INTEGER
    DEFINE result INTEGER

    LET child_node = field_node.getFirstChild()
    LET valuemin = NVL(child_node.getAttribute("valueMin"), 0)
    LET valuemax = NVL(child_node.getAttribute("valueMax"), 100)

    LET result = util.Math.rand(valuemax - valuemin + 1) + valueMin
    RETURN result
END FUNCTION

PRIVATE FUNCTION generate_checkbox(field_node om.DomNode)
    DEFINE child_node om.DomNode
    DEFINE notnull BOOLEAN
    DEFINE valuechecked, valueunchecked STRING
    DEFINE result INTEGER

    LET child_node = field_node.getFirstChild()
    LET notnull = NVL(field_node.getAttribute("notNull"), 0) == 1
    LET valueunchecked = NVL(child_node.getAttribute("valueUnchecked"), FALSE)
    LET valuechecked = NVL(child_node.getAttribute("valueChecked"), TRUE)
    IF notNull THEN
        LET result = util.Math.rand(2)
    ELSE
        LET result = util.Math.rand(3)
    END IF
    CASE result
        WHEN 0
            RETURN valueunchecked
        WHEN 1
            RETURN valuechecked
        OTHERWISE
            RETURN NULL
    END CASE
END FUNCTION

PRIVATE FUNCTION generate_combobox_radiogroup(field_node om.DomNode)
    DEFINE child_node om.DomNode
    DEFINE item_list om.NodeList
    DEFINE result INTEGER
    LET child_node = field_node.getFirstChild()
    LET item_list = child_node.selectByTagName("Item")
    IF item_list.getLength() > 0 THEN
        LET result = util.Math.rand(item_list.getLength()) + 1
        RETURN item_list.item(result).getAttribute("name")
    ELSE
        RETURN NULL
    END IF
END FUNCTION

PRIVATE FUNCTION init_wordlist()
    DEFINE tok base.StringTokenizer
    DEFINE i INTEGER = 0

    LET tok = base.StringTokenizer.create(LOREM_IPSUM, " ")
    WHILE tok.hasMoreTokens()
        LET word_list[i := i + 1] = tok.nextToken().toLowerCase()
        IF word_list[i].getCharAt(word_list[i].getLength()) = "."
                OR word_list[i].getCharAt(word_list[i].getLength()) = ","
            THEN
            LET word_list[i] =
                word_list[i].subString(1, word_list[i].getLength() - 1)
        END IF
    END WHILE
END FUNCTION
