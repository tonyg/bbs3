Program CreateUser;

Uses BBSKrnl;

Var
   T: String;
   I: Byte;
   U: PUser;

Begin
     New(U,Init);
     Write('Enter UserName:  ');
     Readln(U^.Name);
     Write('Enter Phone no.  ');
     Readln(U^.Phone);
     Write('Enter Password:  ');
     Readln(U^.Password);
     Write('Enter Address :  ');
     Readln(U^.Address);
     Write('Enter Access  :  ');
     Readln(U^.Access);
     U^.Settings := 0;
     U^.TotalLogins := 0;
     U^.UserIndex := 0;
     Write('Save?');
     Readln(T);
     If UpStr(T)='YES' then U^.Add;
     Dispose(U,Done);
End.