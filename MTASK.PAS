Unit MTask;

{ Non-Preemptive Multitasking Unit for TP6 ; Version 1.02 }
{ Copyright (C) Tony Garnock-Jones, July 1992 }

Interface

Uses DOS,Crt;

Const
     MaxProcs = 20;

Type
    ProcRec = Record
                StackSeg, StackOfs: Word;
                State: Boolean;
              End;

Var
   Procs: Array[0..MaxProcs] of ProcRec;

Procedure InitTasking;
Procedure Fork;
Procedure Yield;
Procedure KillProc;
Function  IsChild: Boolean;
Function  GetCurrentProcID: Word;
Function  GetLiveTasks: Byte;

Implementation

Var
   OldInt60h, OldExitProc: Pointer;
   TaskingOpen: Boolean;

{$L TASKKRNL.OBJ}

Procedure _InitTasking; Far; External;
Procedure _Int60h; Far; External;

Procedure Error(S: String; C: Word);
Begin
     Writeln(S);
     Halt(C);
End;

Procedure InitTasking;
Var
   I: Integer;
Begin
     If TaskingOpen then Exit;
     _InitTasking;
     Procs[0].State := True;
     For I := 1 to MaxProcs do Procs[I].State := False;
     TaskingOpen := True;
End;

Procedure Fork;
Var
   NewStack: Pointer;
   P: Pointer;
   Err: Boolean;
   W,W2: Word;
Begin
     P := @Procs;
     GetMem(NewStack,$4000);
     While Ofs(NewStack^)<>0 do
     Begin
          FreeMem(NewStack,$4000);
          GetMem(NewStack,$4000);
     End;
     W2 := 0;
     For W := 1 to MaxProcs do
     Begin
          If Procs[W].State=False then W2 := W;
     End;
     If W2=0 then Error('Fork Error. Too many tasks. Halting...',2);
     Asm
                PUSH    DS
                PUSH    ES
                LDS     SI,P
                LES     BX,NEWSTACK
                MOV     AX,0100H
                MOV     DX,W2
                INT     60H
                MOV     ERR,DH
                POP     ES
                POP     DS
     End;
     If Err then Error('Fork Error. Halting...',2);
End;

Procedure Yield;
Var
   P: Pointer;
   Err: Boolean;
Begin
     P := @Procs;
     Asm
                PUSH    DS
                LDS     SI,P
                MOV     AX,0000H
                INT     60H
                MOV     ERR,DH
                POP     DS
     End;
     If Err then Error('Yield Error. Halting...',1);
End;

Procedure KillProc;
Var
   P: Pointer;
   W: Word;
Begin
     If Not(IsChild) then Exit;
     P := @Procs;
     Asm
                PUSH    DS
                LDS     SI,P
                MOV     AX,0200H
                INT     60H
                POP     DS
     End;
     W := GetCurrentProcID;
     P := Ptr(Procs[W].StackSeg,0);
     FreeMem(P,$4000);
End;

Function IsChild;
Var
   ThisP: Word;
   Err: Boolean;
Begin
     Asm
                MOV     AX,0300H
                INT     60H
                MOV     THISP,AX
                MOV     ERR,DH
     End;
     If Err then Error('TaskKrnl Error, Halting...',3);
     IsChild := ThisP<>0;
End;

Function GetCurrentProcID;
Var
   ThisP: Word;
   Err: Boolean;
Begin
     Asm
                MOV     AX,0300H
                INT     60H
                MOV     THISP,AX
                MOV     ERR,DH
     End;
     If Err then Error('TaskKrnl Error, Halting...',3);
     GetCurrentProcID := ThisP;
End;

Function GetLiveTasks; Assembler;
Asm
   MOV AX,0300H
   INT 60H
   MOV AL,DL
End;

{$F+} Procedure MTaskExitProc;
Begin
     SetIntVec($60,OldInt60h);
     ExitProc := OldExitProc;
End; {$F-}

Begin
     TaskingOpen := False;
     InitTasking;
     GetIntVec($60,OldInt60h);
     SetIntVec($60,@_Int60h);
     OldExitProc := ExitProc;
     ExitProc := @MTaskExitProc;
End.