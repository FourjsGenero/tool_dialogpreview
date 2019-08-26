# tool_dialogpreview
Preview a form file with a running dialog

Similar to the Build->Preview action in Genero Studio which opens a form and executes a MENU statement, this progam displays a form and uses dynamic dialogs to build a DIALOG statement from the contents of the form, populate the form with data appropriate to the datatype and widget properties, and thus allow you to preview the form with some data and data-entry

If no argument is passed in, an openFile front-call will occur to allow you to select a .42f compiled form file.

If an argument is passed in, that will be the initial form file

At this stage it has been tested against TABLE and normal inputs. More work is required to add SCROLLGRID, TREE, and Matrix.

At this stage, the dialog built is a Multi-Dialog with INPUT for fields not in a TABLE and INPUT ARRAY for each table found.  Other planned functionality is to allow you to choose between INPUT ARRAY and DISPLAY ARRAY, and similarly INPUT and CONSTRUCT

Various methods are used to generate random data that take into account Data type, Widget type, and various widget attributes.  This can also be enhanced
