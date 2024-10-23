Program BBS3; {Third attempt!}

Uses BBSKrnl, CRT, DOS, MTask, ComLines;

Var
   RootScreen: PScreen;

   Com2: PComLine;
   Com2Ready: Boolean;
   Com2Baud:  Longint;
   Com1: PComLine;
   Com1Ready: Boolean;
   Com1Baud:  Longint;

   Temp: Word;
   C: Char;

Procedure Banner;
Begin
     With RootScreen^ do
     Begin
          SetColor(7,0);
          Cls;
          PutS('BBS3    V1.12e Copyright (C) 1992 Tony Garnock-Jones'+NL);
          PutS('----------------------------------------------------'+NL);
          PutS(NL);
          PutS('  KEYS FROM ANYWHERE:'+NL);
          PutS('Ctrl-L = Start up a LOCAL LOGIN session'+NL);
          PutS('Alt-N  = Select next terminal to view'+NL);
          PutS('Alt-X  = Exit from the program entirely'+NL);
          PutS('Alt-K  = Kick off the user currently selected'+NL);
          PutS(NL);
          PutS('Waiting for login...'+NL);
     End;
End;

Procedure GetSetup;
Var
   F: Text;
   S: String;
   W,W2,C: Word;
   L: Longint;
Begin
     If Not(FileExists('BBS3.CFG')) then Exit;
     Assign(F,'BBS3.CFG');
     Reset(F);
     While Not(Eof(F)) do
     Begin
          Readln(F,S);
          S := UpStr(S);
          If Copy(S,1,4)='COM2' then
          Begin
               Com2Ready := True;
               If Length(S)>4 then
               Begin
                    S := Copy(S,6,Length(S));
                    Val(S,L,C);
                    Com2Baud := L;
                    If Com2Baud=0 then Com2Baud := 2400;
                    S := '';
               End else Com2Baud := 2400;
          End;
          If Copy(S,1,4)='COM1' then
          Begin
               Com1Ready := True;
               If Length(S)>4 then
               Begin
                    S := Copy(S,6,Length(S));
                    Val(S,L,C);
                    Com1Baud := L;
                    If Com1Baud=0 then Com1Baud := 2400;
                    S := '';
               End else Com1Baud := 2400;
          End;
     End;
     Close(F);
End;

Begin
     New(RootScreen,Init);
     Com1Ready := False;
     Com2Ready := False;
     GetSetup;
     If Com2Ready then
     Begin
          New(Com2,Init(2,Com2Baud));
          Com2^.CanDealloc := False;
     End;
     If Com1Ready then
     Begin
          New(Com1,Init(1,Com1Baud));
          Com1^.CanDealloc := False;
     End;
     RootScreen^.DataBarOn := True;
     RootScreen^.ShowUserData := False;
     Banner;
     RootScreen^.Show;
     While Not(GlobalQuit) do
     Begin
          If CurrentTask = GetCurrentProcID then
          Begin
               SelectNextTask;
               If CurrentTask = GetCurrentProcID then
               Begin
                    RootScreen^.Show;
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
                                        End;
                                   End;
                         End;
                    End;
               End;
          End;
          If Com2Ready then Com2^.CheckLogin;
          If Com1Ready then Com1^.CheckLogin;
          If Task0Message = MSG_LOGINCONSOLE then
          Begin
               NewConsole;
               Task0Message := MSG_NONE;
          End;
          Yield;
     End;
     Dispose(RootScreen,Done);
     If Com2Ready then Dispose(Com2,Done);
     If Com1Ready then Dispose(Com1,Done);
     TextAttr := $07;
     ClrScr;
End.