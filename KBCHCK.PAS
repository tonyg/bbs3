Uses Crt;
Var
   Ans: Char;
Begin
     Repeat
           Ans := ReadKey;
           WriteLn(Ans:8,Ord(Ans):15);
     Until Ans = #27;
End.