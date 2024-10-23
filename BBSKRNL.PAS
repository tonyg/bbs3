Unit BBSKrnl; {Kernel for BBS Multi-user attempt 3}

Interface

Uses DOS, CRT, MTask;

Const
     SOH        = #$01;
     EOT        = #$04;
     ACK        = #$06;
     NAK        = #$15;
     CAN        = #$18;

Const
     NoKeyThreshold             = 5610; {300 seconds * 18.7 ticks/sec}{5 min}
     TotalTimeAllowed           = 67320; {3600 sec.  * 18.7 ticks/sec}{1 hr}

     CoSysopAccess              = $7FFFFFFE;
     SysopAccess                = $7FFFFFFF;

     MSG_NONE                   = 00000;
     MSG_SHUTDOWN               = 00001;
     MSG_PAGE                   = 00002;
     MSG_LOGINCONSOLE           = 00003;

     UserFileName : String = 'USERLIST';
     NL = #13#10;

     CurrentChatter: Word = 0;
     Task0Message  : Word = 0;

Type
    PUser = ^TUser;
    TUser = Object
              Name, Phone, Address, Password: String;
              Access, Settings: Longint;
              TotalLogins, UserIndex: Word;

              Constructor Init;
              Destructor  Done;

              Function    Get: Boolean;
              Procedure   Put;
              Procedure   Add;
              Function    Initials: String;
            End;
    PScreen = ^TScreen;
    TScreen = Object
                Buf: Array[0..3999] of Char;
                CurrentAttrib: Char;
                CursX,CursY: Word;
                Scroll: Boolean;
                DataBarOn, ShowUserData: Boolean;

                InAnsiMode: Boolean;
                AnsiString: String;
                SaveX,SaveY: Word;

                Constructor Init;
                Destructor  Done; Virtual;

                Procedure   PutCh(C: Char); Virtual;
                Procedure   PutS(S: String); Virtual;
                Procedure   GotoXY(X,Y: Word); Virtual;
                Procedure   Cls; Virtual;
                Procedure   ClrEol; Virtual;
                Procedure   Show; Virtual;
                Function    GetFore: Byte;
                Function    GetBack: Byte;
                Procedure   SetColor(F,B: Byte);
                Procedure   DataBar;
              End;
    PLine = ^TLine;
    TLine = Object
              CanDealloc: Boolean;
              Screen: PScreen;
              User: PUser;
              CanUse, InUse: Boolean;
              ChatChar: Char;
              Message: Word;
              CurrSect: String;
              LastKeyTime: LongInt;
              TotalTimeOnline: LongInt;
              PassedHalfTime: Boolean;
              LocalCopy: Boolean;
              CmdString: String;

              ReservedL: LongInt;
              ReservedW: Word;

              Constructor Init;
              Destructor  Done; Virtual;
              Procedure   TaskSuicide; Virtual;

              Procedure   OpenUp; Virtual;
              Procedure   CloseDown; Virtual;
              Function    GetCh(Var C: Char): Boolean; Virtual;
              Procedure   PutCh(C: Char); Virtual;
              Function    Name: String; Virtual;
              Procedure   CheckLogin; Virtual;

              Procedure   GetS(Var S: String);
              Function    GetFirstLetter: String;
              Function    GetCmdS: String;
              Procedure   GetShielded(Var S: String);
              Procedure   Out(S: String);
              Procedure   OutLn(S: String);

              Function    GetExpert: Boolean;
              Procedure   SetExpert(X: Boolean);
              Procedure   TypeFile(S: String);

              Procedure   Login;
              Procedure   MainMenu;
              Procedure   Setup;
              Procedure   WhosWho;
              Procedure   Files;
              Procedure   TransferFile(Fname: String; Send: Boolean);
            End;

Var
   GlobalQuit: Boolean;
   CurrentTask: Word;
   TaskList: Array[0..MaxProcs] of PLine;

Function UpStr(S: String): String;
Function GetSysTime: Longint;
Procedure Tone(Freq,Dur: Word);
Procedure Beep;
Procedure AddTask(P: PLine);
Procedure DelTask(P: PLine);
Procedure NewConsole;
Procedure SelectNextTask;
Function FileExists(S: String): Boolean;

Implementation

Procedure CreateEmptyUserFile;
Var
   F: File;
Begin
     Assign(F,UserFileName);
     ReWrite(F);
     Close(F);
End;

Function FileExists;
Var
   Src: SearchRec;
Begin
     FindFirst(S,$FF,Src);
     Yield;
     If DosError<>0 then FileExists := False else
     Begin
          If (Pos('*',S)<>0) or (Pos('?',S)<>0) then FileExists := False else
                                                     FileExists := True;
     End;
End;

Procedure SelectNextTask;
Begin
     Repeat
           CurrentTask := (CurrentTask+1) mod (MaxProcs+1);
     Until Procs[CurrentTask].State;
     If TaskList[CurrentTask]<>Nil then
          TaskList[CurrentTask]^.Screen^.Show;
End;

Procedure NewConsole;
Var
   W: Word;
   FreeSpace: Boolean;
   P: PLine;
Begin
     FreeSpace := False;
     For W := 1 to MaxProcs do If Not(Procs[W].State) then FreeSpace := True;
     If Not(FreeSpace) then
     Begin
          Beep;
          Exit;
     End;
     W := GetCurrentProcID;
     Fork;
     If W<>GetCurrentProcID then
     Begin
          CurrentTask := GetCurrentProcID;
          New(P,Init);
          AddTask(P);
          P^.Login;
          Dispose(P,Done);
          DelTask(P);
          CurrentTask := 0;
          KillProc;
          Yield;
     End;
End;

Procedure AddTask;
Var
   W: Word;
Begin
     W := GetCurrentProcID;
     If TaskList[W]=Nil then TaskList[W] := P;
End;

Procedure DelTask;
Var
   W: Word;
Begin
     W := GetCurrentProcID;
     If TaskList[W]=P then TaskList[W] := Nil;
End;

Function GetSysTime: Longint; Assembler;
Asm
   MOV AX,0000
   INT 1AH
   MOV AX,DX
   MOV DX,CX
End;

Procedure Tone;
Var
   L: Longint;
Begin
     Sound(Freq);
     L := GetSysTime;
     Repeat
           Yield;
     Until GetSysTime-L>Dur;
     NoSound;
End;

Procedure Beep;
Begin
     Tone(440,2);
End;

Function UpStr;
Var
   I: Integer;
   SS: String;
Begin
     For I := 1 to Length(S) do SS[I] := UpCase(S[I]);
     SS[0] := S[0];
     UpStr := SS;
End;

{========================================================== USER}

Constructor TUser.Init;
Var
   I: Integer;
Begin
     Name        := 'UNKNOWN';
     Phone       := Name;
     Address     := Name;
     Password    := Name;
     Access      := 0;
     Settings    := 0;
     TotalLogins := 0;
     UserIndex   := 0;
End;

Destructor TUser.Done;
Begin
End;

Function TUser.Get;
Var
   F: Text;
   P: TUser;
Begin
     If Not(FileExists(UserFileName)) then CreateEmptyUserFile;
     Assign(F,UserFileName);
     Reset(F);
     P.UserIndex := 0;
     While Not(Eof(F)) do
     Begin
          Inc(P.UserIndex);
          Readln(F,P.Name);
          Readln(F,P.Phone);
          Readln(F,P.Address);
          Readln(F,P.Password);
          Readln(F,P.Access);
          Readln(F,P.Settings);
          Readln(F,P.TotalLogins);
          If UpStr(P.Name)=UpStr(Name) then
          Begin
               Close(F);
               Self := P;
               Get := True;
               Exit;
          End;
     End;
     Close(F);
     Get := False;
End;

Procedure TUser.Put;
Var
   FI,FO: Text;
   P: TUser;
Begin
     If Not(FileExists(UserFileName)) then CreateEmptyUserFile;
     Assign(FI,UserFileName);
     Assign(FO,'TEMP.USR');
     Reset(FI);
     Rewrite(FO);

     P.UserIndex := 0;
     While Not(Eof(FI)) do
     Begin
          P.UserIndex := P.UserIndex+1;
          Readln(FI,P.Name);
          Readln(FI,P.Phone);
          Readln(FI,P.Address);
          Readln(FI,P.Password);
          Readln(FI,P.Access);
          Readln(FI,P.Settings);
          Readln(FI,P.TotalLogins);
          If UpStr(P.Name)=UpStr(Name) then
          Begin
               Writeln(FO,Name);
               Writeln(FO,Phone);
               Writeln(FO,Address);
               Writeln(FO,Password);
               Writeln(FO,Access);
               Writeln(FO,Settings);
               Writeln(FO,TotalLogins);
          End else
          Begin
               Writeln(FO,P.Name);
               Writeln(FO,P.Phone);
               Writeln(FO,P.Address);
               Writeln(FO,P.Password);
               Writeln(FO,P.Access);
               Writeln(FO,P.Settings);
               Writeln(FO,P.TotalLogins);
          End;
     End;

     Close(FI);
     Close(FO);
     Erase(FI);
     Rename(FO,UserFileName);
End;

Procedure TUser.Add;
Var
   FI,FO: Text;
   P: TUser;
   Updated: Boolean;
Begin
     Updated := False;
     If Not(FileExists(UserFileName)) then CreateEmptyUserFile;
     Assign(FI,UserFileName);
     Assign(FO,'TEMP.USR');
     Reset(FI);
     Rewrite(FO);

     P.UserIndex := 0;
     While Not(Eof(FI)) do
     Begin
          Inc(P.UserIndex);
          Readln(FI,P.Name);
          Readln(FI,P.Phone);
          Readln(FI,P.Address);
          Readln(FI,P.Password);
          Readln(FI,P.Access);
          Readln(FI,P.Settings);
          Readln(FI,P.TotalLogins);
          If UpStr(P.Name)=UpStr(Name) then
          Begin
               Writeln(FO,Name);
               Writeln(FO,Phone);
               Writeln(FO,Address);
               Writeln(FO,Password);
               Writeln(FO,Access);
               Writeln(FO,Settings);
               Writeln(FO,TotalLogins);
               Updated := True;
          End else
          Begin
               Writeln(FO,P.Name);
               Writeln(FO,P.Phone);
               Writeln(FO,P.Address);
               Writeln(FO,P.Password);
               Writeln(FO,P.Access);
               Writeln(FO,P.Settings);
               Writeln(FO,P.TotalLogins);
          End;
     End;

     If Not(Updated) then
     Begin
          Writeln(FO,Name);
          Writeln(FO,Phone);
          Writeln(FO,Address);
          Writeln(FO,Password);
          Writeln(FO,Access);
          Writeln(FO,Settings);
          Writeln(FO,TotalLogins);
     End;

     Close(FI);
     Close(FO);
     Erase(FI);
     Rename(FO,UserFileName);
End;

Function TUser.Initials;
Var
   S,S2: String;
Begin
     S := Name;
     While Pos(' ',S)<>0 do S := Copy(S,1,Length(S)-1);
     Initials := S;
End;

{========================================================== USER}
{========================================================== SCREEN}

Constructor TScreen.Init;
Begin
     CurrentAttrib := #$07;
     InAnsiMode := False;
     AnsiString := '';
     Scroll := True;
     DataBarOn := False;
     ShowUserData := False;
     Cls;
End;

Destructor TScreen.Done;
Begin
     CurrentAttrib := #$07;
     Cls;
End;

Procedure TScreen.PutCh;
Var
   Index: Word;
   Temp: String;
   Parm: Array[1..20] of Byte;
   PCount: Byte;
   W,WW: Word;
   TextAttr: Byte;
Begin
     If InAnsiMode then
     Begin
          AnsiString := AnsiString + C;
          If C in ['A'..'Z','a'..'z'] then
          Begin
               PCount := 0;
               Temp := '';
               If (Length(AnsiString)>1) and (AnsiString[1]='[') then
               Begin
                    For WW := 2 to Length(AnsiString) do
                        If (AnsiString[WW]=';') or (WW=Length(AnsiString)) and (Temp[0]>#0) then
                        Begin
                             Inc(PCount);
                             Val(Temp,Parm[PCount],W);
                             Temp := '';
                        End Else Temp := Temp + AnsiString[WW];
                    TextAttr := Byte(CurrentAttrib);
                    Case C of
                         'H','f','S','F': If PCount = 0 then GotoXY(1,1) else
                                                             GotoXY(Parm[2],Parm[1]);
                         'A': GotoXY(CursX,CursY-Parm[1]);
                         'B': GotoXY(CursX,CursY+Parm[1]);
                         'C': GotoXY(CursX+Parm[1],CursY);
                         'D': GotoXY(CursX-Parm[1],CursY);
                         's': Begin
                                   SaveX := CursX;
                                   SaveY := CursY;
                              End;
                         'u': GotoXY(SaveX,SaveY);
                         'J': If Parm[1]=2 then Cls;
                         'K': ClrEol;
                         'm': For WW := 1 to PCount do
                              Begin
                                   Case Parm[WW] of
                                        0: TextAttr := $07;
                                        1: TextAttr := TextAttr or $08;
                                        5: TextAttr := TextAttr or $80;
                                        8: TextAttr := (TextAttr and $F0) or (TextAttr shr 4);
                                        30: TextAttr := (TextAttr and $F8) or 0;
                                        31: TextAttr := (TextAttr and $F8) or 4;
                                        32: TextAttr := (TextAttr and $F8) or 2;
                                        33: TextAttr := (TextAttr and $F8) or 6;
                                        34: TextAttr := (TextAttr and $F8) or 1;
                                        35: TextAttr := (TextAttr and $F8) or 5;
                                        36: TextAttr := (TextAttr and $F8) or 3;
                                        37: TextAttr := (TextAttr and $F8) or 7;
                                        40: TextAttr := (TextAttr and $8F) or $00;
                                        41: TextAttr := (TextAttr and $8F) or $40;
                                        42: TextAttr := (TextAttr and $8F) or $20;
                                        43: TextAttr := (TextAttr and $8F) or $60;
                                        44: TextAttr := (TextAttr and $8F) or $10;
                                        45: TextAttr := (TextAttr and $8F) or $50;
                                        46: TextAttr := (TextAttr and $8F) or $30;
                                        47: TextAttr := (TextAttr and $8F) or $70;
                                   End;
                              End;
                    End;
                    CurrentAttrib := Char(TextAttr);
                    InAnsiMode := False;
               End;
          End;
     End else
     Begin
          Index := Pred(CursY)*160+Pred(CursX)*2;
          Case C of
               #13: CursX := 1;
               #10: Inc(CursY);
               #8:  Dec(CursX);
               #12: Cls;
               #27: Begin
                         InAnsiMode := True;
                         AnsiString := '';
                    End;
          Else
              Buf[Index] := C;
              Buf[Index+1] := CurrentAttrib;
              Inc(CursX);
          End;
          If CursX<1 then CursX := 1;
          If CursY<1 then CursY := 1;
          If (CursY>24) and Scroll then
          Begin
               CursY := 24;
               Move(Buf[160],Buf,4000-160);
               For Index := 3840 to 3999 do
               Begin
                    Buf[Index] := #$20;
                    Inc(Index);
                    Buf[Index] := CurrentAttrib;
               End;
          End;
     End;
End;

Procedure TScreen.PutS;
Var
   I: Integer;
Begin
     For I := 1 to Length(S) do PutCh(S[I]);
End;

Procedure TScreen.GotoXY;
Begin
     CursX := X;
     CursY := Y;
End;

Procedure TScreen.Show;
Var
   SaveBuf: Array[0..160] of Char;
Begin
     Move(Buf[3840],SaveBuf,160);
     If DataBarOn then DataBar;
     Move(Buf,Mem[$B800:0000],4000);
     Crt.GotoXY(CursX,CursY);
     Move(SaveBuf,Buf[3840],160);
End;

Function TScreen.GetFore;
Begin
     GetFore := Byte(CurrentAttrib) and $F;
End;

Function TScreen.GetBack;
Begin
     GetBack := Byte(CurrentAttrib) Shr 4;
End;

Procedure TScreen.SetColor;
Begin
     CurrentAttrib := Char((B shl 4) or F);
End;

Procedure TScreen.Cls;
Var
   Index: Integer;
Begin
     For Index := 0 to 3999 do
     Begin
          Buf[Index] := #$20;
          Inc(Index);
          Buf[Index] := CurrentAttrib;
     End;
     GotoXY(1,1);
End;

Procedure TScreen.ClrEol;
Var
   Index: Integer;
   I1,I2: Integer;
Begin
     I1 := Pred(CursY)*160+Pred(CursX)*2;
     I2 := CursY*160-1;
     For Index := I1 to I2 do
     Begin
          Buf[Index] := ' ';
          Inc(Index);
          Buf[Index] := CurrentAttrib;
     End;
End;

Procedure TScreen.DataBar;
Var
   T: Char;
   S: String;
   SX,SY: Word;
Begin
     SX := CursX;
     SY := CursY;
     T := CurrentAttrib;

     SetColor(14,4);
     GotoXY(1,25);
     ClrEol;
     Scroll := False;
     PutS('Current Terminal: ');
     Str(CurrentTask,S);
     If CurrentTask=0 then S := 'ROOT TASK';
     PutS(S);
     If ShowUserData then
     Begin
          PutS(' '+TaskList[CurrentTask]^.User^.Name);
          PutS(' '+TaskList[CurrentTask]^.User^.Password);
          Str(TaskList[CurrentTask]^.User^.Access,S);
          PutS(' '+S);
     End;
     Str(MemAvail,S);
     PutS(' MEMAVAIL:'+S);
     Scroll := True;

     GotoXY(SX,SY);
     CurrentAttrib := T;
End;

{========================================================== SCREEN}
{========================================================== LINE}

Constructor TLine.Init;
Begin
     CanDealloc  := True;
     New(Screen,Init);
     Screen^.DataBarOn := True;
     Screen^.ShowUserData := True;
     New(User,Init);
     CanUse := False;
     InUse  := False;
     ChatChar := #0;
     Message := MSG_NONE;
     LocalCopy := True;
     CmdString   := '';
End;

Destructor TLine.Done;
Begin
     Dispose(Screen,Done);
     Dispose(User,Done);
     CanUse := False;
     InUse  := False;
End;

Procedure TLine.TaskSuicide;
Begin
     DelTask(@Self);
     KillProc;
End;

Procedure TLine.OpenUp;
Begin
     InUse := True;
End;

Procedure TLine.CloseDown;
Begin
     InUse := False;
     If User<>Nil then User^.Put;
     If CurrentTask = GetCurrentProcID then CurrentTask := 0;
End;

Function TLine.GetCh;
Var
   P: PLine;
Begin
{     If (GetSysTime-LastKeyTime>NoKeyThreshold) and (User^.Access<CoSysopAccess) then
     Begin
          OutLn(NL+NL+'You have not pressed a key in the last five minutes, so I presume you have');
          OutLn(      'left the computer. You have been logged out. Thank you for calling.'+NL);
          Message := MSG_SHUTDOWN;
     End;
     If (GetSysTime-TotalTimeOnline>TotalTimeAllowed div 2) and (User^.Access<CoSysopAccess)
        and Not(PassedHalfTime) then
     Begin
          OutLn(NL+NL+'Half your allotted time has passed.'+NL);
          PassedHalfTime := True;
     End;
     If (GetSysTime-TotalTimeOnline>TotalTimeAllowed) and (User^.Access<CoSysopAccess) then
     Begin
          OutLn(NL+NL+'Your allotted time has passed. You have been logged off. Thank you for calling.'+NL);
          Message := MSG_SHUTDOWN;
     End;}
     If Message=MSG_SHUTDOWN then
     Begin
          Message := MSG_NONE;
          CloseDown;
          TaskSuicide;
          P := @Self;
          If CanDealloc then Dispose(P,Done);
          Yield;
     End;
     If Message=MSG_PAGE then
     Begin
          Message := MSG_NONE;
          OutLn(NL+'**** Please go to the WhosWho menu and select (C)hat'+NL);
     End;
     If CurrentTask = GetCurrentProcID then
     Begin
          If KeyPressed then
          Begin
               C := ReadKey;
               Case C of
                    #12: Task0Message := MSG_LOGINCONSOLE;
                    #0:  Begin
                              C := ReadKey;
                              Case C of
                                   #45: GlobalQuit := True;
                                   #49: SelectNextTask;
                                   #37: Message := MSG_SHUTDOWN;
                              End;
                         End;
               Else
                   Yield;
                   GetCh := True;
                   Exit;
               End;
               Yield;
               GetCh := False;
               Exit;
          End else
          Begin
               Yield;
               GetCh := False;
               Exit;
          End;
     End;
     Yield;
     GetCh := False;
End;

Procedure TLine.PutCh;
Var
   P: PLine;
Begin
     If Message=MSG_SHUTDOWN then
     Begin
          Message := MSG_NONE;
          CloseDown;
          TaskSuicide;
          P := @Self;
          If CanDealloc then Dispose(P,Done);
          Yield;
     End;
     If LocalCopy then Screen^.PutCh(C);
End;

Function TLine.Name;
Begin
     Name := 'CONSOLE';
End;

Procedure TLine.GetS;
Var
   C: Char;
   SS: String;
Begin
     C := ' ';
     S := '';
     While C<>#13 do
     Begin
          If GetCh(C) then
          Begin
               If C<>#27 then
               Begin
                    If (C>=#32) or (C=#8) then
                    Begin
                         PutCh(C);
                         If CurrentTask = GetCurrentProcID then
                              Screen^.Show;
                    End;
                    If C=#8 then
                    Begin
                         If Length(S)=0 then
                         Begin
                              Out(#27+'[1C');
                         End Else
                         Begin
                              Out(' '+#8);
                              S := Copy(S,1,Length(S)-1);
                         End;
                    End Else
                    Begin
                         If C=#24 then
                         Begin
                              Str(Length(S),SS);
                              Out(#27+'['+SS+'D');
                              Out(#27+'[K');
                              S  := '';
                              SS := '';
                         End else If C>=#32 then S := S+C;
                    End;
               End;
          End;
          Yield;
     End;
     Out(NL);
End;

Function TLine.GetFirstLetter;
Var
   S: String;
Begin
     If Length(CmdString)>0 then
     Begin
          S := Copy(CmdString,1,1);
          CmdString := Copy(CmdString,2,Length(CmdString));
     End else
     Begin
          GetS(CmdString);
          If Length(CmdString)=0 then S := '' else S := GetFirstLetter;
     End;
     GetFirstLetter := S;
End;

Function TLine.GetCmdS;
Var
   S: String;
Begin
     If Length(CmdString)=0 then GetS(CmdString);
     S := CmdString;
     CmdString := '';
     GetCmdS := S;
End;

Procedure TLine.GetShielded;
Var
   C: Char;
Begin
     CmdString := '';
     C := ' ';
     S := '';
     While C<>#13 do
     Begin
          If GetCh(C) then
          Begin
               If C<>#27 then
               Begin
                    If C=#8 then
                    Begin
                         S := Copy(S,1,Length(S)-1);
                    End Else If C<>#13 then S := S+C;
               End;
          End;
          Yield;
     End;
     Out(NL);
End;

Procedure TLine.Out;
Var
   I: Integer;
   C: Integer;
Begin
     C := 0;
     For I := 1 to Length(S) do
     Begin
          PutCh(S[I]);
          Inc(C);
          If C=5 then
          Begin
               C := 0;
               Yield;
          End;
     End;
     If CurrentTask = GetCurrentProcID then
          Screen^.Show;
End;

Procedure TLine.OutLn;
Begin
     Out(S);
     Out(NL);
End;

Function TLine.GetExpert;
Begin
     GetExpert := (User^.Settings and $01)<>0;
End;

Procedure TLine.SetExpert;
Begin
     If X then User^.Settings := User^.Settings or $01 else
               User^.Settings := User^.Settings and Not($01);
End;

Procedure TLine.TypeFile;
Var
   F: Text;
   SS: String;
   C: Char;
   L: Longint;
Begin
     L := 0;
     If Not(FileExists(S)) then Exit;
     Assign(F,S);
     Yield;
     Reset(F);
     Yield;
     While Not(Eof(F)) do
     Begin
          Readln(F,SS);
          OutLn(SS);
          Inc(L);
          If L>=23 then
          Begin
               Out('     <<ANY KEY TO CONTINUE>>');
               Repeat Until GetCh(C);
               Out(NL);
               L := 0;
          End;
          If GetCh(C) then
             If C in [' ',#27 {ESC},#3 {Control-C}] then
             Begin
                  Close(F);
                  Yield;
                  Exit;
             End;
          Yield;
     End;
     Close(F);
     Yield;
End;

Procedure TLine.CheckLogin;
Var
   W: Word;
Begin
     If InUse then Exit;
     W := GetCurrentProcID;
     Fork;
     If W<>GetCurrentProcID then
     Begin
          AddTask(@Self);
          Login;
          If CurrentTask = GetCurrentProcID then CurrentTask := 0;
          TaskSuicide;
     End;
End;

Procedure TLine.Login;
Var
   C: Char;
   CountTimes: Word;
   Success: Boolean;
   SS: String;
Function AlreadyOnLine: Boolean;
Var
   I: Integer;
Begin
     If User^.Access>=CoSysopAccess then
     Begin
          AlreadyOnLine := False;
          Exit;
     End;
     For I := 1 to MaxProcs do
         If TaskList[I]<>Nil then
            Begin
                 If TaskList[I]^.User^.Name = User^.Name then
                    If TaskList[I] <> @Self then
                       Begin
                            AlreadyOnLine := True;
                            Exit;
                       End;
            End;
     AlreadyOnLine := False;
End;
Begin
     LastKeyTime := GetSysTime;
     TotalTimeOnline := GetSysTime;
     PassedHalfTime := False;
     OpenUp;
     Dispose(User,Done);
     New(User,Init);
     ChatChar := #0;
     While GetCh(C) do;
     Out(#12);
     TypeFile('Login.Txt');
     Success := False;
     CountTimes := 0;
     Repeat
           CurrSect := 'Login';
           Out(NL+'Enter your Username:     ');
           GetS(User^.Name);
           If Not(User^.Get) then
           Begin
                OutLn(NL+'New Users are not accepted. If you would like to join this BBS,');
                OutLn('you must speak with the Sysop privately.');
                OutLn(NL);
           End else
           Begin
                Out('Enter your Password:     ');
                GetShielded(SS);
                If Not(AlreadyOnLine) then
                Begin
                     If UpStr(SS)=UpStr(User^.Password) then
                     Begin
                          Inc(User^.TotalLogins);
                          Success := True;
                          MainMenu;
                     End else Out(NL);
                End else OutLn('You are already online!'+NL);
           End;
           Inc(CountTimes);
     Until (CountTimes>=3) or Success;
     CloseDown;
End;

Procedure TLine.MainMenu;
Var
   S: String;
   Logout: Boolean;
Procedure CheckLogout;
Var
   S: String;
Begin
     OutLn(NL+NL+'Really Log Out? [y N] ');
     S := GetFirstLetter;
     If UpStr(Copy(S,1,1))='Y' then Logout := True else
                                    Logout := False;
End;
Begin
     Logout := False;
     Str(User^.TotalLogins,S);
     Out(NL+'This is your '+S);
     If (User^.TotalLogins mod 10)=1 then Out('st') else
        If (User^.TotalLogins mod 10)=2 then Out('nd') else
           If (User^.TotalLogins mod 10)=3 then Out('rd') else
              Out('th');
     OutLn(' login!'+NL);
     While Not(Logout) do
     Begin
          CurrSect := 'Main_Menu';
          If Not(GetExpert) then
          Begin
               Out(NL+NL);
               TypeFile('MainMenu.Txt');
          End;
          OutLn('');
          Out('MAIN MENU [B F G M S W X ?]: ');
          S := GetFirstLetter;
          S := Copy(UpStr(S),1,1);
{          If S='B' then Bulletins;}
          If S='F' then Files;
          If S='G' then CheckLogout;
{          If S='M' then Messages;}
          If S='S' then Setup;
          If S='W' then WhosWho;
          If S='X' then SetExpert(Not(GetExpert));
          If (S='') or (S='?') then
          Begin
               If GetExpert then
               Begin
                    Out(NL+NL);
                    TypeFile('MainMenu.Txt');
               End;
          End;
     End;
End;

Procedure TLine.Setup;
Var
   S: String;
Procedure ListData;
Var
   S: String;
Begin
     Out(NL+NL);
     OutLn('Name        :'+User^.Name+NL);
     OutLn('Phone Number:'+User^.Phone);
     OutLn('Address     :'+User^.Address);
     Str(User^.Access,S);
     OutLn('Access Level:'+S+NL);
     If GetExpert then S := 'TRUE' else
                       S := 'FALSE';
     OutLn('Default XpertMode   : '+S);
     Str(User^.TotalLogins,S);
     OutLn('Total Logins to date: '+S);
     Str(User^.UserIndex,S);
     OutLn('User index          : '+S);
End;
Procedure PhoneChange;
Var
   S: String;
Begin
     OutLn(NL+NL);
     OutLn('Old Phone Number: '+User^.Phone);
     Out('Change it? [y N] ');
     S := GetFirstLetter;
     If UpStr(Copy(S,1,1))='Y' then
     Begin
          Out(NL+NL+'Enter New Phone Number : ');
          User^.Phone := GetCmdS;
     End;
End;
Procedure PasswordChange;
Var
   S,S2: String;
Begin
     OutLn(NL+NL);
     Out('Do you want to change your password? [y N] ');
     S := GetFirstLetter;
     If UpStr(Copy(S,1,1))='Y' then
     Begin
          Out(NL+NL+'Enter your old Password: ');
          GetShielded(S);
          S := UpStr(S);
          If S<>UpStr(User^.Password) then
          Begin
               OutLn('Incorrect password.'+NL);
               Exit;
          End;
          Out('Enter your new Password: ');
          GetShielded(S);
          S := UpStr(S);
          Out('Enter your new Password again, for verification: ');
          GetShielded(S2);
          S2 := UpStr(S2);
          If S<>S2 then
          Begin
               OutLn('The two versions of your new password did not match.'+NL+
                     'The password was not changed.'+NL);
               Exit;
          End;
          User^.Password := S;
          OutLn('Your password has been changed.'+NL);
     End;
End;
Procedure AddressChange;
Begin
     OutLn(NL+NL);
     OutLn('Old Address: '+User^.Address);
     Out('Change it? [y N] ');
     S := GetFirstLetter;
     If UpStr(Copy(S,1,1))='Y' then
     Begin
          Out(NL+NL+'Enter New Address: ');
          CmdString := '';
          GetS(User^.Address);
     End;
End;
Begin
     Repeat
           CurrSect := 'Setup';
           If Not(GetExpert) then
           Begin
                Out(NL+NL);
                TypeFile('Setup.Txt');
           End;
           OutLn('');
           Out('SETUP MENU [A L N P Q X ?]: ');
           S := GetFirstLetter;
           S := UpStr(S);

           If (S='') or (S='?') then
              If GetExpert then
              Begin
                   Out(NL+NL);
                   TypeFile('Setup.Txt');
              End;

           If Length(S)>0 then
              Case S[1] of
                   'L': ListData;
                   'N': PhoneChange;
                   'A': AddressChange;
                   'P': PasswordChange;
                   'X': SetExpert(Not(GetExpert));
              End;
     Until S[1]='Q';
End;

Procedure TLine.WhosWho;
Var
   S: String;
Procedure JoinConference;
Var
   QuitConf: Boolean;
   OldCurrentChatter: Word;
   W: Word;
   C: Char;
   Procedure ConfWrite(C: Char);
   Begin
        Case C of
             #0: Exit;
             #8: Out(#8+' '+#8);
             #13: Out(NL+TaskList[CurrentChatter]^.User^.Initials+'>');
        Else Out(C); End;
        If Screen^.CursX>70 then ConfWrite(#13);
   End;
Begin
     OldCurrentChatter := CurrentChatter;
     CurrentChatter := GetCurrentProcID;
     QuitConf := False;
     CurrSect := 'Chatting';
     OutLn(NL+'Joining Chat conference....'+NL+
           'Ctrl-X to exit...'+NL+
           '==========================================================================');
     Repeat
           If GetCh(C) then
           Begin
                Case C of
                     #24: Begin
                               QuitConf := True;
                               ChatChar := #0;
                          End;
                     #0..#23,#25..#255: Begin
                                             ChatChar := C;
                                             CurrentChatter := GetCurrentProcID;
                                        End;
                End;
           End Else ChatChar := #0;
           If OldCurrentChatter<>CurrentChatter then
           Begin
                If TaskList[CurrentChatter]^.ChatChar<>#13 then
                   Out(NL+TaskList[CurrentChatter]^.User^.Initials+'>');
           End;
           For W := 1 to MaxProcs do
           Begin
                If TaskList[W]<>Nil then
                   ConfWrite(TaskList[W]^.ChatChar);
           End;
           OldCurrentChatter := CurrentChatter;
     Until QuitConf;
     Out(#27+'[1;32m');
End;
Procedure ListTasks;
Var
   W: Word;
   S: String;
Begin
     OutLn(NL+'Current Tasks:');
     OutLn('Number    Process                       User');
     OutLn('==================================================================');
     For W := 1 to MaxProcs do
     Begin
          If TaskList[W]<>Nil then
          Begin
               Str(W,S);
               While Length(S)<10 do S := S+' ';
               Out(S);
               S := TaskList[W]^.CurrSect;
               While Length(S)<30 do S := S+' ';
               Out(S);
               OutLn(TaskList[W]^.User^.Name);
          End;
     End;
     Out(NL);
End;
Procedure PageUser;
Var
   S: String;
   W,C: Word;
Begin
     OutLn(NL+'Select User to page:');
     ListTasks;
     Out(NL);
     Out(#27+'[1AEnter User Number [Q=Quit]-> '+#27+'[K');
     Repeat
           S := GetCmdS;
           Out(#27+'[1AEnter User Number [Q=Quit]-> '+#27+'[K');
           Val(S,W,C);
     Until ((TaskList[W]<>Nil) and (W<=MaxProcs)) or (Copy(UpStr(S),1,1)='Q');
     If Copy(UpStr(S),1,1)='Q' then
     Begin
          OutLn(NL);
          Exit;
     End;
     OutLn(NL);
     If W=GetCurrentProcID then
     Begin
          OutLn('You can''t page yourself!');
          Exit;
     End;
     TaskList[W]^.Message := MSG_PAGE;
     OutLn(TaskList[W]^.User^.Name+' has now been paged...');
End;
Procedure UserList;
Var
   F: Text;
   W: Word;
   S: String;
Begin
     If Not(FileExists(UserFileName)) then CreateEmptyUserFile;
     Assign(F,UserFileName);
     Reset(F);
     W := 0;
     OutLn('Index     Name');
     OutLn('====================================================================');
     While Not(Eof(F)) do
     Begin
          Inc(W);
          Str(W,S);
          While Length(S)<10 do S := S+' ';
          Out(S);
          Readln(F,S);
          OutLn(S);
          Readln(F,S);
          Readln(F,S);
          Readln(F,S);
          Readln(F,S);
          Readln(F,S);
          Readln(F,S);
     End;
     Close(F);
End;
Begin
     Repeat
           CurrSect := 'WhosWho';
           If Not(GetExpert) then
           Begin
                Out(NL+NL);
                TypeFile('WHOSWHO.TXT');
           End;
           OutLn('');
           Out('WHO''S WHO MENU [C L P Q U X ?]: ');
           S := GetFirstLetter;
           S := UpStr(S);

           If (S='') or (S='?') then
              If GetExpert then
              Begin
                   Out(NL+NL);
                   TypeFile('WHOSWHO.TXT');
              End;

           If (Length(S)>0) then
              Case S[1] of
                   'C': JoinConference;
                   'L': ListTasks;
                   'P': PageUser;
                   'U': UserList;
                   'X': SetExpert(Not(GetExpert));
              End;
     Until S[1]='Q';
End;

Procedure TLine.Files;
Var
   S: String;
   CurrArea: String;
Function AreaSelect: Boolean;
Var
   F: Text;
   SS: String;
   L: LongInt;
   C: Word;
Begin
     OutLn(NL+'File areas available :-'+NL);
     TypeFile('FILES\AREADATA.TXT');
     Repeat
           Out(NL+'Enter your selection (0=Cancel) -> ');
           SS := GetCmdS;
     Until SS<>'';
     Val(SS,L,C);
     If L=0 then
     Begin
          OutLn('Cancelled.');
          AreaSelect := False;
     End else
     Begin
          If Not(FileExists('FILES\AREADATA.TXT')) then Exit;
          Assign(F,'FILES\AREADATA.TXT');
          Reset(F);
          C := 0;
          While Not(Eof(F)) do
          Begin
               Inc(C);
               Readln(F,SS);
               If C=L then
               Begin
                    While Copy(SS,1,1)<>' ' do SS := Copy(SS,2,Length(SS));
                    While Copy(SS,1,1) =' ' do SS := Copy(SS,2,Length(SS));
                    While Pos(' ',SS)>0 do SS := Copy(SS,1,Length(SS)-1);
                    CurrArea := 'FILES\'+SS;
                    Close(F);
                    AreaSelect := True;
                    Exit;
               End;
          End;
          OutLn('Invalid area number.');
          AreaSelect := False;
          Close(F);
     End;
End;
Procedure ListFiles;
Var
   F: Text;
   SS: String;
   L: Longint;
   C: Word;
   Line: Byte;
Begin
     If Not(FileExists(CurrArea+'\FILELIST.TXT')) then
     Begin
          OutLn(NL+'You do not have summary access to this area. This is probably because it is');
          OutLn(   'a private area, or the FILELIST.TXT file is missing.'+NL);
          Exit;
     End;
     Assign(F,CurrArea+'\FILELIST.TXT');
     Reset(F);
     OutLn(NL+'Name         Size(K)  Description');
     OutLn(   '=============================================================================');
     Line := 0;
     While Not(Eof(F)) do
     Begin
          Readln(F,SS);
          While Length(SS)<13 do SS := SS+' ';
          Out(SS);
          Readln(F,SS);
          Val(SS,L,C);
          L := L div 1024;
          Str(L,SS);
          While Length(SS)<9 do SS := SS+' ';
          Out(SS);
          Readln(F,SS);
          OutLn(SS);
          Inc(Line);
          If Line>=22 then
          Begin
               Out('     <<ANY KEY TO CONTINUE>>');
               Repeat Until GetCh(SS[1]);
               Out(NL);
               Line := 0;
          End;
     End;
     Close(F);
End;
Procedure FileDownload;
Var
   FName: String;
Begin
     Out(NL+'Enter filename to download: ');
     FName := GetCmdS;
     If Not(FileExists(CurrArea+'\'+FName)) then
     Begin
          OutLn(NL+'Invalid filename or File Not Found...');
          Exit;
     End;
     TransferFile(CurrArea+'\'+FName,True);
End;
Begin
     If Not(FileExists('FILES')) then Exit;
     CurrArea := '';
     If Not(AreaSelect) then Exit;
     Repeat
           CurrSect := 'Files';
           If Not(GetExpert) then
           Begin
                Out(NL+NL);
                TypeFile('FILEMENU.TXT');
           End;
           OutLn('');
           Out('FILES MENU [A D S U M Q X ?]: ');
           S := GetFirstLetter;
           S := UpStr(S);

           If (S='') or (S='?') then
              If GetExpert then
              Begin
                   Out(NL+NL);
                   TypeFile('FILEMENU.TXT');
              End;

           If (Length(S)>0) then
              Case S[1] of
                   'A': If AreaSelect then ;
                   'D': FileDownload;
                   'S': ListFiles;
{                   'U': FileUpload;}
                   'X': SetExpert(Not(GetExpert));
              End;
     Until S[1]='Q';
End;

Procedure TLine.TransferFile;
Var
   SS: String;
Procedure XModem_Send(N: String);
Var
   F: File of Char;
   C: Char;
   W,W2: Word;
   B: Boolean;
   BlockNum: Byte;
   CkSum: Byte;
   L,TickStart: LongInt;
   S: String;
   TheBlock: Array[0..127] of Char;
   HadErrors: Boolean;
Function InTimer(Var C: Char; Timeout: Longint): Boolean;
Var
   L: LongInt;
Begin
     L := GetSysTime;
     While (GetSysTime-L<Timeout) do
     Begin
          If GetCh(C) then
          Begin
               InTimer := True;
               Exit;
          End;
     End;
     InTimer := False;
End;
Procedure SendBlock;
Var
   W: Word;
Begin
     PutCh(SOH);
     PutCh(Char(BlockNum));
     PutCh(Char(255-BlockNum));
     Cksum := 0;
     For W := 0 to 127 do
     Begin
          PutCh(TheBlock[W]);
          Cksum := (Cksum + Byte(TheBlock[W])) and $FF;
     End;
     PutCh(Char(Cksum));
End;
Function ReadBlock: Boolean;
Var
   W: Word;
   B: Boolean;
Begin
     For W := 0 to 127 do TheBlock[W] := #26; {EOF character}
     B := Not(Eof(F));
     For W := 0 to 127 do
         If Not(Eof(F)) then Read(F,TheBlock[W]) else
         Begin
              ReadBlock := B;
              Exit;
         End;
     ReadBlock := B;
End;
Begin
     OutLn('Ready to send '+N+' XModem-Checksum...'+NL);
     TickStart := GetSysTime;
     LocalCopy := False;
     HadErrors := False;
     Assign(F,N);
     Reset(F);
     L := GetSysTime;
     B := False;
     Repeat
           If InTimer(C,19) then
           Begin
                If C=NAK then B := True;
           End;
     Until (GetSysTime-L>=1122) or B;
     If Not(B) then
     Begin
          Close(F);
          L := GetSysTime; Repeat Until GetSysTime-L>=37;
          LocalCopy := True;
          OutLn(NL+NL+'*** XMODEM Download of '+N+' had errors.'+NL);
          Exit;
     End;
     BlockNum := 1;
     B := True;
     While ReadBlock and B do
     Begin
          B := False;
          W := 0;
          Repeat
                SendBlock;
                If InTimer(C,187) then
                Begin
                     If C=ACK then B := True else
                     Begin
                          While InTimer(C,19) do ;
                          HadErrors := True;
                     End;
                End;
                Inc(W);
          Until (W>=10) or B;
          BlockNum := (BlockNum + Byte(B)) mod 256; {If B then Inc(BlockNum)}
     End;
     If B then
     Begin
          PutCh(EOT);
          If Not(InTimer(C,1122)) then HadErrors := True;
     End;
     L := GetSysTime; Repeat Until GetSysTime-L>=37;
     L := FileSize(F);
     Close(F);
     LocalCopy := True;
     Out(NL+NL+'*** XMODEM Download of '+N);
     If HadErrors then OutLn(' had errors.'+NL) else
                       OutLn(' complete.'  +NL);
     L := Round(L/((GetSysTime-TickStart)/18.7));
     Str(L,S);
     OutLn('CPS: '+S);
End;
Procedure XModem_Receive(N: String);
Begin
End;
Begin
     CurrSect := 'File_';
     If Send then CurrSect := CurrSect+'DL' else
                  CurrSect := CurrSect+'UL';
     SS := FName;
     While Pos('\',SS)>0 do SS := Copy(SS,2,Length(SS));
     CurrSect := CurrSect+' ('+SS+')';
     OutLn(NL+'Select protocol to use:');
     OutLn('X: XModem (DEFAULT)');
     OutLn('Q: Cancel');
     Out(NL+'>> ');
     SS := GetFirstLetter;
     SS := UpStr(SS);
     If Length(SS)>0 then
        Case SS[1] of
             'X': If Send then XModem_Send(Fname) else
                               XModem_Receive(Fname);
             'Q': Exit;
        End else
        If Send then XModem_Send(Fname) else
                     XModem_Receive(Fname);
End;

{========================================================== LINE}

Var
   OldExitProc: Pointer;

{$F+} Procedure BBSExitProc;
Var
   I: Integer;
Begin
     For I := 1 to MaxProcs do
     Begin
          If TaskList[I]<>Nil then TaskList[I]^.Message := MSG_SHUTDOWN;
     End;
     Repeat
           Yield;
           I := GetLiveTasks;
     Until GetLiveTasks=1;
     ExitProc := OldExitProc;
End; {$F-}

Var
   Temp: Word;

Begin
     OldExitProc := ExitProc;
     ExitProc := @BBSExitProc;
     For Temp := 0 to MaxProcs do TaskList[Temp] := Nil;
     GlobalQuit := False;
     CurrentTask := 0;
End.
