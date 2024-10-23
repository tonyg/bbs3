Unit ComLines;

Interface

Uses ObjASync, BBSKrnl, MTask;

Type
    PComLine = ^TComLine;
    TComLine = Object(TLine)
                 Port: PASyncPort;
                 ThePort: Word;
                 PortBaud: LongInt;

                 Constructor Init(APort: Word; Baud: Longint);
                 Destructor  Done; Virtual;

                 Procedure   OpenUp; Virtual;
                 Procedure   CloseDown; Virtual;
                 Function    GetCh(Var C: Char): Boolean; Virtual;
                 Procedure   PutCh(C: Char); Virtual;
                 Function    Name: String; Virtual;
                 Procedure   CheckLogin; Virtual;
               End;

Implementation

Constructor TComLine.Init;
Begin
     TLine.Init;
     New(Port,Init);

     ThePort := APort;
     PortBaud:= Baud;

     If Port^.OpenPort(APort,Baud) then
     Begin
          CanUse := True;
          Out('ATS0=1'+NL);
     End else CanUse := False;
End;

Destructor TComLine.Done;
Var
   C: Char;
Begin
     Repeat
           Port^.Hangup;
     Until Not(Port^.Carrier);
     Port^.ClosePort;
     If Port^.OpenPort(ThePort,PortBaud) then
     Begin
          Screen^.CurrentAttrib := #$07;
          Screen^.Cls;
          Screen^.DataBarOn := False;
          Out('ATS0=0'+NL);
     End;
     TLine.Done;
     Dispose(Port,Done);
End;

Procedure TComLine.OpenUp;
Var
   L: Longint;
Begin
     TLine.OpenUp;
     OutLn('Please wait...'+NL);
     L := GetSysTime;
     Repeat
           Yield;
     Until GetSysTime-L>80;
End;

Procedure TComLine.CloseDown;
Var
   P,B: LongInt;
Begin
     Repeat
           Port^.Hangup;
           Yield;
     Until Not(Port^.Carrier);
     TLine.CloseDown;
     Port^.ClosePort;
     If Port^.OpenPort(ThePort,PortBaud) then
     Begin
          CanUse := True;
          Out('ATS0=1'+NL);
     End else CanUse := False;
     If CurrentTask = GetCurrentProcID then CurrentTask := 0;
End;

Function TComLine.GetCh;
Var
   T: Boolean;
Begin
     If Not(Port^.Carrier) and InUse then
     Begin
          CloseDown;
          TaskSuicide;
          Yield;
     End;
     T := TLine.GetCh(C);
     If T=False then
     Begin
          If Port^.ComAvail then
          Begin
               C := Port^.GetCh;
               T := True;
          End else T := False;
     End;
     GetCh := T;
End;

Procedure TComLine.PutCh;
Begin
     If Not(Port^.Carrier) and InUse then
     Begin
          CloseDown;
          TaskSuicide;
          Yield;
     End;
     TLine.PutCh(C);
     Port^.PutCh(C);
End;

Function TComLine.Name;
Var
   S: String;
Begin
     Str(ThePort,S);
     Name := 'COM'+S;
End;

Procedure TComLine.CheckLogin;
Var
   W: Word;
Begin
     If InUse then Exit;
     If Not(CanUse) then Exit;
     If Port^.Carrier then
     Begin
          InUse := True;
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
End;

End.
