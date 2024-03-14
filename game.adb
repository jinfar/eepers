with Text_IO; use Text_IO;
with Interfaces.C; use Interfaces.C;
with Raylib; use Raylib;
with Raymath; use Raymath;
with Ada.Strings.Unbounded;
use Ada.Strings.Unbounded;
with Ada.Containers.Vectors;
with Ada.Unchecked_Deallocation;
with Ada.Containers.Hashed_Maps;
use Ada.Containers;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings;
with Ada.Exceptions; use Ada.Exceptions;

procedure Game is
    DEVELOPMENT : constant Boolean := True;

    type Palette is (
      COLOR_BACKGROUND,
      COLOR_FLOOR,
      COLOR_WALL,
      COLOR_BARRICADE,
      COLOR_PLAYER,
      COLOR_DOOR,
      COLOR_KEY,
      COLOR_BOMB,
      COLOR_LABEL,
      COLOR_SHREK,
      COLOR_CHECKPOINT,
      COLOR_EXPLOSION,
      COLOR_HEALTHBAR);

    Palette_Names: constant array (Palette) of Unbounded_String := [
      COLOR_BACKGROUND => To_Unbounded_String("Background"),
      COLOR_FLOOR      => To_Unbounded_String("Floor"),
      COLOR_WALL       => To_Unbounded_String("Wall"),
      COLOR_Barricade  => To_Unbounded_String("Barricade"),
      COLOR_PLAYER     => To_Unbounded_String("Player"),
      COLOR_DOOR       => To_Unbounded_String("Door"),
      COLOR_KEY        => To_Unbounded_String("Key"),
      COLOR_BOMB       => To_Unbounded_String("Bomb"),
      COLOR_LABEL      => To_Unbounded_String("Label"),
      COLOR_SHREK      => To_Unbounded_String("Shrek"),
      COLOR_CHECKPOINT => To_Unbounded_String("Checkpoint"),
      COLOR_EXPLOSION  => To_Unbounded_String("Explosion"),
      COLOR_HEALTHBAR  => To_Unbounded_String("Healthbar")
      ];
    
    type Byte is mod 256;
    type HSV_Comp is (Hue, Sat, Value);
    type HSV is array (HSV_Comp) of Byte;

    Palette_RGB: array (Palette) of Color := [others => (A => 255, others => 0)];
    Palette_HSV: array (Palette) of HSV := [others => [others => 0]];

    procedure Save_Colors(File_Name: String) is
        F: File_Type;
    begin
        Create(F, Out_File, File_Name);
        for C in Palette loop
            Put(F, To_String(Palette_Names(C)));
            for Comp in HSV_Comp loop
                Put(F, Palette_HSV(C)(Comp)'Image);
            end loop;
            Put_Line(F, "");
        end loop;
        Close(F);
    end;

    procedure Load_Colors(File_Name: String) is
        F: File_Type;
        Line_Number : Integer := 0;
    begin
        Open(F, In_File, File_Name);
        while not End_Of_File(F) loop
            Line_Number := Line_Number + 1;
            declare
                Line: Unbounded_String := To_Unbounded_String(Get_Line(F));

                function Chop_By(Src: in out Unbounded_String; Pattern: String) return Unbounded_String is
                    Space_Index: constant Integer := Index(Src, Pattern);
                    Result: Unbounded_String;
                begin
                    if Space_Index = 0 then
                        Result := Src;
                        Src := Null_Unbounded_String;
                    else
                        Result := Unbounded_Slice(Src, 1, Space_Index - 1);
                        Src := Unbounded_Slice(Src, Space_Index + 1, Length(Src));
                    end if;

                    return Result;
                end;
                function Find_Color_By_Key(Key: Unbounded_String; Co: out Palette) return Boolean is
                begin
                    for C in Palette loop
                        if Key = Palette_Names(C) then
                            Co := C;
                            return True;
                        end if;
                    end loop;
                    return False;
                end;
                C: Palette;
                Key: constant Unbounded_String := Chop_By(Line, " ");
            begin
                Line := Trim(Line, Ada.Strings.Left);
                if Find_Color_By_Key(Key, C) then
                    Line := Trim(Line, Ada.Strings.Left);
                    Palette_HSV(C)(Hue) := Byte'Value(To_String(Chop_By(Line, " ")));
                    Line := Trim(Line, Ada.Strings.Left);
                    Palette_HSV(C)(Sat) := Byte'Value(To_String(Chop_By(Line, " ")));
                    Line := Trim(Line, Ada.Strings.Left);
                    Palette_HSV(C)(Value) := Byte'Value(To_String(Chop_By(Line, " ")));
                    Palette_RGB(C) := Color_From_HSV(C_Float(Palette_HSV(C)(Hue))/255.0*360.0, C_Float(Palette_HSV(C)(Sat))/255.0, C_Float(Palette_HSV(C)(Value))/255.0);
                else
                    Put_Line(File_Name & ":" & Line_Number'Image & "WARNING: Unknown Palette Color: """ & To_String(Key) & """");
                end if;
            end;
        end loop;
        Close(F);
    exception
        when E: Name_Error =>
            Put_Line("WARNING: could not load colors from file " & File_Name & ": " & Exception_Message(E));
    end;

    --  TODO(tool): implement the palette editor
    --  COLOR_BACKGROUND : constant Color := Get_Color(16#0b1424ff#);
    --  COLOR_FLOOR      : constant Color := Get_Color(16#2f2f2fFF#);
    --  COLOR_WALL       : constant Color := Get_Color(16#000000FF#);
    --  COLOR_PLAYER     : constant Color := Get_Color(16#3e89ffff#);
    --  COLOR_DOOR       : constant Color := Get_Color(16#ff9700ff#);
    --  COLOR_KEY        : constant Color := Get_Color(16#ff9700ff#);
    --  COLOR_LABEL      : constant Color := Get_Color(16#FFFFFFFF#);
    --  COLOR_SHREK      : constant Color := Get_Color(16#97FF00FF#);
    --  COLOR_CHECKPOINT : constant Color := Get_Color(16#FF00FFFF#);

    --  COLOR_RED        : constant Color := Get_Color(16#FF0000FF#);
    --  COLOR_PURPLE     : constant Color := Get_Color(16#FF00FFFF#);

    --  TODO(tool): move this to a hotreloadable config
    TURN_DURATION_SECS      : constant Float := 0.125;
    SHREK_ATTACK_COOLDOWN   : constant Integer := 10;
    SHREK_EXPLOSION_DAMAGE  : constant Float := 0.15;
    SHREK_TURN_REGENERATION : constant Float := 0.01;
    BOMB_GENERATOR_COOLDOWN : constant Integer := 20;
    SHREK_STEPS_LIMIT       : constant Integer := 4;
    SHREK_STEP_LENGTH_LIMIT : constant Integer := 100;

    type IVector2 is record
        X, Y: Integer;
    end record;

    Shrek_Size: constant IVector2 := (3, 3);
    type Cell is (None, Floor, Wall, Barricade, Door, Explosion);
    Cell_Size : constant Vector2 := (x => 50.0, y => 50.0);

    function Cell_Colors(C: Cell) return Color is
    begin
        case C is
            when None      => return Palette_RGB(COLOR_BACKGROUND);
            when Floor     => return Palette_RGB(COLOR_FLOOR);
            when Wall      => return Palette_RGB(COLOR_WALL);
            when Barricade => return Palette_RGB(COLOR_BARRICADE);
            when Door      => return Palette_RGB(COLOR_DOOR);
            when Explosion => return Palette_RGB(COLOR_EXPLOSION);
        end case;
    end;

    type Shrek_Path is array (Positive range <>, Positive range <>) of Integer;
    type Shrek_Path_Access is access Shrek_Path;
    procedure Delete_Shrek_Path is new Ada.Unchecked_Deallocation(Shrek_Path, Shrek_Path_Access);
    type Map is array (Positive range <>, Positive range <>) of Cell;
    type Map_Access is access Map;
    procedure Delete_Map is new Ada.Unchecked_Deallocation(Map, Map_Access);

    function "<="(A, B: IVector2) return Boolean is
    begin
        return A.X <= B.X and then A.Y <= B.Y;
    end;

    function "<"(A, B: IVector2) return Boolean is
    begin
        return A.X < B.X and then A.Y < B.Y;
    end;

    function "="(A, B: IVector2) return Boolean is
    begin
        return A.X = B.X and then A.Y = B.Y;
    end;

    function "+"(A, B: IVector2) return IVector2 is
    begin
        return (A.X + B.X, A.Y + B.Y);
    end;

    function Equivalent_IVector2(Left, Right: IVector2) return Boolean is
    begin
        return Left.X = Right.X and then Left.Y = Right.Y;
    end;

    function Hash_IVector2(V: IVector2) return Hash_Type is
        M31: constant Hash_Type := 2**31-1; -- a nice Mersenne prime
    begin
        return Hash_Type(V.X) * M31 + Hash_Type(V.Y);
    end;

    type Item_Kind is (Key, Bomb, Checkpoint);

    type Item(Kind: Item_Kind := Key) is record
        case Kind is
            when Bomb =>
                Cooldown: Integer;
            when others => null;
        end case;
    end record;

    package Hashed_Map_Items is new
        Ada.Containers.Hashed_Maps(
            Key_Type => IVector2,
            Element_Type => Item,
            Hash => Hash_IVector2,
            Equivalent_Keys => Equivalent_IVector2);

    function To_Vector2(iv: IVector2) return Vector2 is
    begin
        return (X => C_float(iv.X), Y => C_float(iv.Y));
    end;

    type Player_State is record
        Prev_Position: IVector2;
        Position: IVector2;
        Keys: Integer := 0;
        Bombs: Integer := 1;
        Bomb_Slots: Integer := 1;
        Dead: Boolean := False;
    end record;

    type Shrek_State is record
        Prev_Position: IVector2;
        Position: IVector2;
        Health: Float := 1.0;
        Attack_Cooldown: Integer := SHREK_ATTACK_COOLDOWN;
        Path: Shrek_Path_Access;
        Dead: Boolean;
    end record;

    type Bomb_State is record
        Position: IVector2;
        Countdown: Integer := 0;
    end record;

    type Bomb_State_Array is array (1..10) of Bomb_State;

    type Checkpoint_State is record
        Map: Map_Access := Null;
        Player_Position: IVector2;
        Player_Keys: Integer;
        Player_Bombs: Integer;
        Player_Bomb_Slots: Integer;
        Shrek_Position: IVector2;
        Shrek_Health: Float;
        Shrek_Dead: Boolean;
        Items: Hashed_Map_Items.Map;
    end record;

    type Game_State is record
        Map: Map_Access := Null;
        Player: Player_State;
        Shrek: Shrek_State;

        Turn_Animation: Float := 0.0;

        Items: Hashed_Map_Items.Map;
        Bombs: Bomb_State_Array;
        Camera_Position: Vector2 := (x => 0.0, y => 0.0);
        Camera_Velocity: Vector2 := (x => 0.0, y => 0.0);

        Checkpoint: Checkpoint_State;
    end record;

    function Clone_Map(M0: Map_Access) return Map_Access is
        M1: Map_Access;
    begin
        M1 := new Map(M0'Range(1), M0'Range(2));
        M1.all := M0.all;
        return M1;
    end;

    function Inside_Of_Rect(Start, Size, Point: in IVector2) return Boolean is
    begin
        return Start <= Point and then Point < Start + Size;
    end;

    type Direction is (Left, Right, Up, Down);

    procedure Step(D: in Direction; Position: in out IVector2) is
    begin
        case D is
            when Left  => Position.X := Position.X - 1;
            when Right => Position.X := Position.X + 1;
            when Up    => Position.Y := Position.Y - 1;
            when Down  => Position.Y := Position.Y + 1;
        end case;
    end;

    function Opposite(D: Direction) return Direction is
    begin
        case D is
            when Left  => return Right;
            when Right => return Left;
            when Up    => return Down;
            when Down  => return Up;
        end case;
    end;

    function Contains_Walls(Game: Game_State; Start, Size: IVector2) return Boolean is
    begin
        for X in Start.X..Start.X+Size.X-1 loop
            for Y in Start.Y..Start.Y+Size.Y-1 loop
                if Game.Map(Y, X) = Wall then
                    return True;
                end if;
            end loop;
        end loop;
        return False;
    end;

    procedure Recompute_Shrek_Path(Game: in out Game_State) is
        package Queue is new
          Ada.Containers.Vectors(Index_Type => Natural, Element_Type => IVector2);

        Q: Queue.Vector;
    begin
        for Y in Game.Shrek.Path'Range(1) loop
            for X in Game.Shrek.Path'Range(2) loop
                Game.Shrek.Path(Y, X) := -1;
            end loop;
        end loop;

        for Dy in 0..Shrek_Size.Y-1 loop
            for Dx in 0..Shrek_Size.X-1 loop
                declare
                    Position: constant IVector2 := (Game.Player.Position.X - Dx, Game.Player.Position.Y - Dy);
                begin
                    if not Contains_Walls(Game, Position, Shrek_Size) then
                        Game.Shrek.Path(Position.Y, Position.X) := 0;
                        Q.Append(Position);
                    end if;
                end;
            end loop;
        end loop;

        while not Q.Is_Empty loop
            declare
                Position: constant IVector2 := Q(0);
            begin
                Q.Delete_First;

                if Position = Game.Shrek.Position then
                    exit;
                end if;

                if Game.Shrek.Path(Position.Y, Position.X) >= SHREK_STEPS_LIMIT then
                    exit;
                end if;

                for Dir in Direction loop
                    declare
                        New_Position: IVector2 := Position;
                    begin
                        Step(Dir, New_Position);
                        for Limit in 1..SHREK_STEP_LENGTH_LIMIT loop
                            if Contains_Walls(Game, New_Position, Shrek_Size) then
                                exit;
                            end if;
                            if Game.Shrek.Path(New_Position.Y, New_Position.X) < 0 then
                                Game.Shrek.Path(New_Position.Y, New_Position.X) := Game.Shrek.Path(Position.Y, Position.X) + 1;
                                Q.Append(New_Position);
                            end if;
                            Step(Dir, New_Position);
                        end loop;
                    end;
                end loop;
            end;
        end loop;
    end;

    procedure Game_Save_Checkpoint(Game: in out Game_State) is
    begin
        if Game.Checkpoint.Map /= null then
            Delete_Map(Game.Checkpoint.Map);
        end if;
        Game.Checkpoint.Map               := Clone_Map(Game.Map);
        Game.Checkpoint.Player_Position   := Game.Player.Position;
        Game.Checkpoint.Player_Keys       := Game.Player.Keys;
        Game.Checkpoint.Player_Bombs      := Game.Player.Bombs;
        Game.Checkpoint.Player_Bomb_Slots := Game.Player.Bomb_Slots;
        Game.Checkpoint.Shrek_Position    := Game.Shrek.Position;
        Game.Checkpoint.Shrek_Dead        := Game.Shrek.Dead;
        Game.Checkpoint.Shrek_Health      := Game.Shrek.Health;
        Game.Checkpoint.Items             := Game.Items;
    end;

    procedure Game_Restore_Checkpoint(Game: in out Game_State) is
    begin
        if Game.Map /= null then
            Delete_Map(Game.Map);
        end if;
        Game.Map := Clone_Map(Game.Checkpoint.Map);
        Game.Player.Position   := Game.Checkpoint.Player_Position;
        Game.Player.Keys       := Game.Checkpoint.Player_Keys;
        Game.Player.Bombs      := Game.Checkpoint.Player_Bombs;
        Game.Player.Bomb_Slots := Game.Checkpoint.Player_Bomb_Slots;
        Game.Shrek.Position    := Game.Checkpoint.Shrek_Position;
        Game.Shrek.Dead        := Game.Checkpoint.Shrek_Dead;
        Game.Shrek.Health      := Game.Checkpoint.Shrek_Health;
        Game.Items             := Game.Checkpoint.Items;
    end;

    procedure Load_Game_From_File(File_Name: in String; Game: in out Game_State; Update_Player: Boolean) is
        package Rows is new
            Ada.Containers.Vectors(
                Index_Type => Natural,
                Element_Type => Unbounded_String);
        F: File_Type;
        Map_Rows: Rows.Vector;
        Width: Integer := 0;
        Height: Integer := 0;
    begin
        Open(F, In_File, File_Name);
        while not End_Of_File(F) loop
            declare
                Line: constant String := Get_Line(F);
            begin
                if Line'Length > Width then
                    Width := Line'Length;
                end if;
                Map_Rows.Append(To_Unbounded_String(Line));
                Height := Height + 1;
            end;
        end loop;
        Close(F);

        if Game.Map /= null then
            Delete_Map(Game.Map);
        end if;
        Game.Map := new Map(1..Height, 1..Width);

        if Game.Shrek.Path /= null then
            Delete_Shrek_Path(Game.Shrek.Path);
        end if;
        Game.Shrek.Path := new Shrek_Path(1..Height, 1..Width);

        Game.Items.Clear;
        for Bomb of Game.Bombs loop
            Bomb.Countdown := 0;
        end loop;

        for Row in Game.Map'Range(1) loop
            declare
                Map_Row: constant Unbounded_String := Map_Rows(Row - 1);
            begin
                Put_Line(To_String(Map_Rows(Row - 1)));
                for Column in Game.Map'Range(2) loop
                    if Column in 1..Length(Map_Row) then
                        case Element(Map_Row, Column) is
                            when 'B' =>
                                Game.Shrek.Position := (Column, Row);
                                Game.Shrek.Prev_Position := (Column, Row);
                                Game.Shrek.Health := 1.0;
                                Game.Shrek.Dead := False;
                                Game.Map(Row, Column) := Floor;
                            when '.' => Game.Map(Row, Column) := Floor;
                            when '#' => Game.Map(Row, Column) := Wall;
                            when '=' => Game.Map(Row, Column) := Door;
                            when '!' =>
                                Game.Map(Row, Column) := Floor;
                                Game.Items.Insert((Column, Row), (Kind => Checkpoint));
                            when '*' =>
                                Game.Map(Row, Column) := Floor;
                                Game.Items.Insert((Column, Row), (Kind => Bomb, Cooldown => 0));
                            when '&' =>
                                Game.Map(Row, Column) := Barricade;
                            when '%' =>
                                Game.Map(Row, Column) := Floor;
                                Game.Items.Insert((Column, Row), (Kind => Key));
                            when '@' =>
                                Game.Map(Row, Column) := Floor;
                                if Update_Player then
                                    Game.Player.Position := (Column, Row);
                                    Game.Player.Prev_Position := (Column, Row);
                                end if;
                            when others => Game.Map(Row, Column) := None;
                        end case;
                    else
                        Game.Map(Row, Column) := None;
                    end if;
                end loop;
            end;
        end loop;
    end;

    procedure Draw_Bomb(Position: IVector2; C: Color) is
    begin
        Draw_Circle_V(To_Vector2(Position)*Cell_Size + Cell_Size*0.5, Cell_Size.X*0.5, C);
    end;

    procedure Draw_Key(Position: IVector2) is
    begin
        Draw_Circle_V(To_Vector2(Position)*Cell_Size + Cell_Size*0.5, Cell_Size.X*0.25, Palette_RGB(COLOR_KEY));
    end;

    procedure Draw_Number(Start, Size: Vector2; N: Integer; C: Color) is
        Label: constant Char_Array := To_C(Trim(Integer'Image(N), Ada.Strings.Left));
        Label_Height: constant Integer := 32;
        Label_Width: constant Integer := Integer(Measure_Text(Label, Int(Label_Height)));
        Text_Size: constant Vector2 := To_Vector2((Label_Width, Label_Height));
        Position: constant Vector2 := Start + Size*0.5 - Text_Size*0.5;
    begin
        Draw_Text(Label, Int(Position.X), Int(Position.Y), Int(Label_Height), C);
    end;

    procedure Draw_Number(Cell_Position: IVector2; N: Integer; C: Color) is
    begin
        Draw_Number(To_Vector2(Cell_Position)*Cell_Size, Cell_Size, N, C);
    end;

    procedure Game_Cells(Game: in Game_State) is
    begin
        for Row in Game.Map'Range(1) loop
            for Column in Game.Map'Range(2) loop
                declare
                    Position: constant Vector2 := To_Vector2((Column, Row))*Cell_Size;
                begin
                    Draw_Rectangle_V(position, cell_size, Cell_Colors(Game.Map(Row, Column)));
                    if DEVELOPMENT then
                        if Is_Key_Down(KEY_P) then
                            Draw_Number((Column, Row), Game.Shrek.Path(Row, Column), (A => 255, others => 0));
                        end if;
                    end if;
                end;
            end loop;
        end loop;
    end;

    procedure Game_Items(Game: in Game_State) is
        use Hashed_Map_Items;
    begin
        for C in Game.Items.Iterate loop
            case Element(C).Kind is
                when Key => Draw_Key(Key(C));
                when Checkpoint =>
                    declare
                        Checkpoint_Item_Size: constant Vector2 := Cell_Size*0.5;
                    begin
                        Draw_Rectangle_V(To_Vector2(Key(C))*Cell_Size + Cell_Size*0.5 - Checkpoint_Item_Size*0.5, Checkpoint_Item_Size, Palette_RGB(COLOR_CHECKPOINT));
                    end;
                when Bomb =>
                    if Element(C).Cooldown > 0 then
                        Draw_Bomb(Key(C), Color_Brightness(Palette_RGB(COLOR_BOMB), -0.5));
                        Draw_Number(Key(C), Element(C).Cooldown, Palette_RGB(COLOR_LABEL));
                    else
                        Draw_Bomb(Key(C), Palette_RGB(COLOR_BOMB));
                    end if;
            end case;
        end loop;
    end;

    procedure Player_Step(Game: in out Game_State; Dir: Direction) is
    begin
        Game.Player.Prev_Position := Game.Player.Position;
        Game.Turn_Animation := 1.0;
        Step(Dir, Game.Player.Position);
        case Game.Map(Game.Player.Position.Y, Game.Player.Position.X) is
           when Floor =>
               declare
                   use Hashed_Map_Items;
                   C: Cursor := Game.Items.Find(Game.Player.Position);
               begin
                   if Has_Element(C) then
                       case Element(C).Kind is
                          when Key =>
                              Game.Player.Keys := Game.Player.Keys + 1;
                              Game.Items.Delete(C);
                          when Bomb => if Game.Player.Bombs < Game.Player.Bomb_Slots and then Element(C).Cooldown <= 0 then
                              Game.Player.Bombs := Game.Player.Bombs + 1;
                              Game.Items.Replace_Element(C, (Kind => Bomb, Cooldown => BOMB_GENERATOR_COOLDOWN));
                          end if;
                          when Checkpoint =>
                              Game.Items.Delete(C);
                              Game_Save_Checkpoint(Game);
                       end case;
                   end if;
               end;
           when Door =>
               if Game.Player.Keys > 0 then
                   Game.Player.Keys := Game.Player.Keys - 1;
                   Game.Map(Game.Player.Position.Y, Game.Player.Position.X) := Floor;
               else
                   Step(Opposite(Dir), Game.Player.Position);
               end if;
           when others =>
               Step(Opposite(Dir), Game.Player.Position);
        end case;
    end;

    procedure Explode(Game: in out Game_State; Position: in IVector2) is
        procedure Explode_Line(Dir: Direction) is
            New_Position: IVector2 := Position;
        begin
            Line: for I in 1..10 loop
                if New_Position = Game.Player.Position then
                    Game.Player.Dead := True;
                end if;
                -- TODO: explosion should not damage Shrek repeatedly
                if not Game.Shrek.Dead and then Inside_Of_Rect(Game.Shrek.Position, Shrek_Size, New_Position) then
                    Game.Shrek.Health := Game.Shrek.Health - SHREK_EXPLOSION_DAMAGE;
                    if Game.Shrek.Health <= 0.0 then
                        Game.Shrek.Dead := True;
                    end if;
                end if;
                case Game.Map(New_Position.Y, New_Position.X) is
                   when Floor | Explosion =>
                       Game.Map(New_Position.Y, New_Position.X) := Explosion;
                       Step(Dir, New_Position);
                   when Barricade =>
                       Game.Map(New_Position.Y, New_Position.X) := Explosion;
                       return;
                   when others =>
                       return;
                end case;
            end loop Line;
        end;
    begin
        for Dir in Direction loop
            Explode_Line(Dir);
        end loop;
    end;

    Keys: constant array (Direction) of int := [
        Left  => KEY_A,
        Right => KEY_D,
        Up    => KEY_W,
        Down  => KEY_S
    ];

    function Screen_Size return Vector2 is
    begin
        return To_Vector2((Integer(Get_Screen_Width), Integer(Get_Screen_Height)));
    end;

    procedure Game_Update_Camera(Game: in out Game_State) is
        Camera_Target: constant Vector2 :=
          Screen_Size*0.5 - To_Vector2(Game.Player.Position)*Cell_Size - Cell_Size*0.5;
    begin
        Game.Camera_Position := Game.Camera_Position + Game.Camera_Velocity*Get_Frame_Time;
        Game.Camera_Velocity := (Camera_Target - Game.Camera_Position)*2.0;
    end;

    function Game_Camera(Game: in Game_State) return Camera2D is
    begin
        return (
          offset => Game.Camera_Position,
          target => (x => 0.0, y => 0.0),
          rotation => 0.0,
          zoom => 1.0);
    end;

    function Interpolate_Positions(IPrev_Position, IPosition: IVector2; T: Float) return Vector2 is
        Prev_Position: constant Vector2 := To_Vector2(IPrev_Position)*Cell_Size;
        Curr_Position: constant Vector2 := To_Vector2(IPosition)*Cell_Size;
    begin
        return Prev_Position + (Curr_Position - Prev_Position)*C_Float(1.0 - T);
    end;

    Space_Down: Boolean := False;
    Dir_Pressed: array (Direction) of Boolean := [others => False];
    
    procedure Swallow_Player_Input is
    begin
        Space_Down := False;
        Dir_Pressed := [others => False];
    end;

    procedure Game_Player(Game: in out Game_State) is
    begin
        if Game.Player.Dead then
            --  TODO: when the player revives themselves they are
            --  being put into bomb selection mode which is weird
            if Space_Down then
                Game_Restore_Checkpoint(Game);
                Game.Player.Dead := False;
            end if;

            return;
        end if;

        if Game.Turn_Animation > 0.0 then
            Draw_Rectangle_V(Interpolate_Positions(Game.Player.Prev_Position, Game.Player.Position, Game.Turn_Animation), Cell_Size, Palette_RGB(COLOR_PLAYER));
            return;
        end if;

        Draw_Rectangle_V(To_Vector2(Game.Player.Position)*Cell_Size, Cell_Size, Palette_RGB(COLOR_PLAYER));
        if Space_Down and then Game.Player.Bombs > 0 then
            for Dir in Direction loop
                declare
                    Position: IVector2 := Game.Player.Position;
                begin
                    Step(Dir, Position);
                    if Game.Map(Position.Y, Position.X) = Floor then
                        Draw_Bomb(Position, Palette_RGB(COLOR_BOMB));
                        if Dir_Pressed(Dir) then
                            for Bomb of Game.Bombs loop
                                if Bomb.Countdown <= 0 then
                                    Bomb.Countdown := 3;
                                    Bomb.Position := Position;
                                    exit;
                                end if;
                            end loop;
                            Game.Player.Bombs := Game.Player.Bombs - 1;
                        end if;
                    end if;
                end;
            end loop;
        else
            for Dir in Direction loop
                if Dir_Pressed(Dir) then
                    for Y in Game.Map'Range(1) loop
                        for X in Game.Map'Range(2) loop
                            if Game.Map(Y, X) = Explosion then
                                Game.Map(Y, X) := Floor;
                            end if;
                        end loop;
                    end loop;

                    Player_Step(Game, Dir);
                    Recompute_Shrek_Path(Game);

                    for Bomb of Game.Bombs loop
                        if Bomb.Countdown > 0 then
                            Bomb.Countdown := Bomb.Countdown - 1;
                            if Bomb.Countdown <= 0 then
                                Explode(Game, Bomb.Position);
                            end if;
                        end if;
                    end loop;

                    declare
                        use Hashed_Map_Items;
                    begin
                        for C in Game.Items.Iterate loop
                            if Element(C).Kind = Bomb then
                                if Element(C).Cooldown > 0 then
                                    Game.Items.Replace_Element(C, (Kind => Bomb, Cooldown => Element(C).Cooldown - 1));
                                end if;
                            end if;
                        end loop;
                    end;

                    if not Game.Shrek.Dead then
                        Game.Shrek.Prev_Position := Game.Shrek.Position;
                        -- TODO: Shrek should attack on zero just like a bomb.
                        if Game.Shrek.Attack_Cooldown <= 0 then
                            declare
                                Current : constant Integer := Game.Shrek.Path(Game.Shrek.Position.Y, Game.Shrek.Position.X);
                            begin
                                -- TODO: maybe pick the paths
                                --  randomly to introduce a bit of
                                --  RNG into this pretty
                                --  deterministic game
                                Search: for Dir in Direction loop
                                    declare
                                        Position: IVector2 := Game.Shrek.Position;
                                    begin
                                        while not Contains_Walls(Game, Position, Shrek_Size) loop
                                            Step(Dir, Position);
                                            if Game.Shrek.Path(Position.Y, Position.X) = Current - 1 then
                                                Game.Shrek.Position := Position;
                                                exit Search;
                                            end if;
                                        end loop;
                                    end;
                                end loop Search;
                            end;
                            Game.Shrek.Attack_Cooldown := SHREK_ATTACK_COOLDOWN;
                        else
                            Game.Shrek.Attack_Cooldown := Game.Shrek.Attack_Cooldown - 1;
                        end if;
                        if Inside_Of_Rect(Game.Shrek.Position, Shrek_Size, Game.Player.Position) then
                            Game.Player.Dead := True;
                        end if;
                        if Game.Shrek.Health < 1.0 then
                           Game.Shrek.Health := Game.Shrek.Health + SHREK_TURN_REGENERATION;
                        end if;
                    end if;
                end if;
            end loop;
        end if;
    end;

    procedure Game_Bombs(Game: Game_State) is
    begin
        for Bomb of Game.Bombs loop
            if Bomb.Countdown > 0 then
                Draw_Bomb(Bomb.Position, Palette_RGB(COLOR_BOMB));
                Draw_Number(Bomb.Position, Bomb.Countdown, Palette_RGB(COLOR_LABEL));
            end if;
        end loop;
    end;

    procedure Game_Hud(Game: in Game_State) is
    begin
        for Index in 1..Game.Player.Keys loop
            declare
                Position: constant Vector2 := (100.0 + C_float(Index - 1)*Cell_Size.X, 100.0);
            begin
                Draw_Circle_V(Position, Cell_Size.X*0.25, Palette_RGB(COLOR_KEY));
            end;
        end loop;

        for Index in 1..Game.Player.Bombs loop
            declare
                Position: constant Vector2 := (100.0 + C_float(Index - 1)*Cell_Size.X, 200.0);
            begin
                Draw_Circle_V(Position, Cell_Size.X*0.5, Palette_RGB(COLOR_BOMB));
            end;
        end loop;

        if Game.Player.Dead then
            declare
                Label: constant Char_Array := To_C("Ded");
                Label_Height: constant Integer := 48;
                Label_Width: constant Integer := Integer(Measure_Text(Label, Int(Label_Height)));
                Text_Size: constant Vector2 := To_Vector2((Label_Width, Label_Height));
                Position: constant Vector2 := Screen_Size*0.5 - Text_Size*0.5;
            begin
                Draw_Text(Label, Int(Position.X), Int(Position.Y), Int(Label_Height), Palette_RGB(COLOR_LABEL));
            end;
        end if;
    end;

    procedure Health_Bar(Boundary_Start, Boundary_Size: Vector2; Health: C_Float) is
        Health_Padding: constant C_Float := 20.0;
        Health_Height: constant C_Float := 10.0;
        Health_Width: constant C_Float := Boundary_Size.X*Health;
    begin
        Draw_Rectangle_V(
          Boundary_Start - (0.0, Health_Padding + Health_Height),
          (Health_Width, Health_Height),
          Palette_RGB(COLOR_HEALTHBAR));
    end;

    procedure Game_Shrek(Game: in out Game_State) is
        Position: constant Vector2 :=
          (if Game.Turn_Animation > 0.0
           then Interpolate_Positions(Game.Shrek.Prev_Position, Game.Shrek.Position, Game.Turn_Animation)
           else To_Vector2(Game.Shrek.Position)*Cell_Size);
        Size: constant Vector2 := To_Vector2(Shrek_Size)*Cell_Size;
    begin
        if Game.Shrek.Dead then
            return;
        end if;
        Draw_Rectangle_V(Position, Cell_Size*3.0, Palette_RGB(COLOR_SHREK));
        Health_Bar(Position, Size, C_Float(Game.Shrek.Health));
        Draw_Number(Position, Size, Game.Shrek.Attack_Cooldown, (A => 255, others => 0));
    end;

    Game: Game_State;
    Title: constant Char_Array := To_C("Hello, NSA");
    
    Palette_Editor: Boolean := False;
    Palette_Editor_Choice: Palette := Palette'First;
    Palette_Editor_Selected: Boolean := False;
    Palette_Editor_Component: HSV_Comp := Hue;
begin
    --  Put("Background"); Put_HSV(Color_To_HSV(COLOR_BACKGROUND)); Put_Line("");
    --  Put("Floor");      Put_HSV(Color_To_HSV(COLOR_FLOOR));      Put_Line("");
    --  Put("Wall");       Put_HSV(Color_To_HSV(COLOR_WALL));       Put_Line("");
    --  Put("Player");     Put_HSV(Color_To_HSV(COLOR_PLAYER));     Put_Line("");
    --  Put("Door");       Put_HSV(Color_To_HSV(COLOR_DOOR));       Put_Line("");
    --  Put("Key");        Put_HSV(Color_To_HSV(COLOR_KEY));        Put_Line("");
    --  Put("Label");      Put_HSV(Color_To_HSV(COLOR_LABEL));      Put_Line("");
    --  Put("Shrek");      Put_HSV(Color_To_HSV(COLOR_SHREK));      Put_Line("");
    --  Put("Checkpoint"); Put_HSV(Color_To_HSV(COLOR_CHECKPOINT)); Put_Line("");
    --  return;

    Load_Colors("colors.txt");
    Load_Game_From_File("map.txt", Game, True);
    Game_Save_Checkpoint(Game);
    Put_Line("Keys: " & Integer'Image(Game.Player.Keys));
    Set_Config_Flags(FLAG_WINDOW_RESIZABLE);
    Init_Window(800, 600, Title);
    Set_Target_FPS(60);
    Set_Exit_Key(KEY_NULL);
    while Window_Should_Close = 0 loop
        Begin_Drawing;
            Clear_Background(Palette_RGB(COLOR_BACKGROUND));

            Space_Down := Boolean(Is_Key_Down(KEY_SPACE));
            for Dir in Direction loop
                Dir_Pressed(Dir) := Boolean(Is_Key_Pressed(Keys(Dir)));
            end loop;

            if DEVELOPMENT then
                if Is_Key_Pressed(KEY_R) then
                    Load_Game_From_File("map.txt", Game, False);
                    Game_Save_Checkpoint(Game);
                end if;

                if Is_Key_Pressed(KEY_O) then
                    Palette_Editor := not Palette_Editor;
                    if not Palette_Editor then
                        Save_Colors("colors.txt");
                    end if;
                end if;

                if Palette_Editor then
                    if Palette_Editor_Selected then
                        if Is_Key_Pressed(KEY_ESCAPE) then
                            Palette_Editor_Selected := False;
                        end if;

                        if Is_Key_Pressed(Keys(Left)) then
                            if Palette_Editor_Component /= HSV_Comp'First then
                                Palette_Editor_Component := HSV_Comp'Pred(Palette_Editor_Component);
                            end if;
                        end if;

                        if Is_Key_Pressed(Keys(Right)) then
                            if Palette_Editor_Component /= HSV_Comp'Last then
                                Palette_Editor_Component := HSV_Comp'Succ(Palette_Editor_Component);
                            end if;
                        end if;
                        
                        if Is_Key_Down(Keys(Up)) then
                            Palette_HSV(Palette_Editor_Choice)(Palette_Editor_Component) := Palette_HSV(Palette_Editor_Choice)(Palette_Editor_Component) + 1;
                            Palette_RGB(Palette_Editor_Choice) := Color_From_HSV(C_Float(Palette_HSV(Palette_Editor_Choice)(Hue))/255.0*360.0, C_Float(Palette_HSV(Palette_Editor_Choice)(Sat))/255.0, C_Float(Palette_HSV(Palette_Editor_Choice)(Value))/255.0);
                        end if;
                        
                        if Is_Key_Down(Keys(Down)) then
                            Palette_HSV(Palette_Editor_Choice)(Palette_Editor_Component) := Palette_HSV(Palette_Editor_Choice)(Palette_Editor_Component) - 1;
                            Palette_RGB(Palette_Editor_Choice) := Color_From_HSV(C_Float(Palette_HSV(Palette_Editor_Choice)(Hue))/255.0*360.0, C_Float(Palette_HSV(Palette_Editor_Choice)(Sat))/255.0, C_Float(Palette_HSV(Palette_Editor_Choice)(Value))/255.0);
                        end if;
                    else 
                        if Is_Key_Pressed(Keys(Down)) then
                            if Palette_Editor_Choice /= Palette'Last then
                                Palette_Editor_Choice := Palette'Succ(Palette_Editor_Choice);
                            end if;
                        end if;

                        if Is_Key_Pressed(Keys(Up)) then
                            if Palette_Editor_Choice /= Palette'First then
                                Palette_Editor_Choice := Palette'Pred(Palette_Editor_Choice);
                            end if;
                        end if;

                        if Is_Key_Pressed(KEY_ESCAPE) then
                            Palette_Editor := False;
                        end if;
                        
                        if Is_Key_Pressed(KEY_ENTER) then
                            Palette_Editor_Selected := True;
                        end if;
                    end if;
                    
                    Swallow_Player_Input;
                end if;

                --  TODO(tool): save current checkpoint to file for debug purposes
            end if;

            if Game.Turn_Animation > 0.0 then
                Game.Turn_Animation := (Game.Turn_Animation*TURN_DURATION_SECS - Float(Get_Frame_Time))/TURN_DURATION_SECS;
            end if;

            Game_Update_Camera(Game);
            Begin_Mode2D(Game_Camera(Game));
                Game_Cells(Game);
                Game_Items(Game);
                Game_Player(Game);
                Game_Shrek(Game);
                Game_Bombs(Game);
            End_Mode2D;

            Game_Hud(Game);
            Draw_FPS(10, 10);

            if Palette_Editor then
                for C in Palette loop
                    declare
                        Label: constant Char_Array := To_C(To_String(Palette_Names(C)));
                        Label_Height: constant Integer := 32;
                        Position: constant Vector2 := (200.0, 200.0 + C_Float(Palette'Pos(C))*C_Float(Label_Height));
                    begin
                        Draw_Text(Label, Int(Position.X), Int(Position.Y), Int(Label_Height),
                          (if not Palette_Editor_Selected and C = Palette_Editor_Choice
                           then (R => 255, A => 255, others => 0)
                           else (others => 255)));
                           
                        for Comp in HSV_Comp loop
                            declare
                                Label: constant Char_Array := To_C(Comp'Image & ": " & Palette_HSV(C)(Comp)'Image);
                                Label_Height: constant Integer := 32;
                                Position: constant Vector2 := (
                                    X => 600.0 + 200.0*C_Float(HSV_Comp'Pos(Comp)),
                                    Y => 200.0 + C_Float(Palette'Pos(C))*C_Float(Label_Height)
                                );
                            begin
                                Draw_Text(Label, Int(Position.X), Int(Position.Y), Int(Label_Height),
                                  (if Palette_Editor_Selected and C = Palette_Editor_Choice and Comp = Palette_Editor_Component
                                   then (R => 255, A => 255, others => 0)
                                   else (others => 255)));
                            end;
                        end loop;
                    end;
                end loop;
            end if;
        End_Drawing;
    end loop;
    Close_Window;
end;

--  TODO: mechanics to skip a turn
--  TODO: placing a bomb is not a turn (should it be tho?)
--  TODO: tutorial does not "explain" how to place bomb
--  TODO: keep steping while you are holding a certain direction
--    Cause constantly tapping it feels like ass
--  TODO: count the player's turns towards the final score of the game
--    We can even collect different stats, like bombs collected, bombs used,
--    times deid etc.
--  TODO: animate key when you pick it up
--    Smoothly move it into the HUD.
