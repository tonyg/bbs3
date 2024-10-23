Unit ObjASync; {ASync Comms unit encapsulated}

Interface

Uses Dos, CRT;

Const
     Buffer_Max = 4096;

Type
    PAsyncPort= ^ASyncPort;
    AsyncPort = Object
                  OriginalVector: Pointer;
                  IsPortOpen: Boolean;
                  ComPort, BasePort, IRQ: Word;

                  Constructor Init;
                  Destructor  Done;

                  Function    OpenPort(ThePort: Word; BaudRate: Longint): Boolean;
                  Procedure   ClosePort;
                  Function    ComAvail: Boolean;
                  Function    GetCh: Char;
                  Procedure   PutCh(C: Char);
                  Procedure   Hangup;
                  Function    Carrier: Boolean;
                End;

Implementation

Const
     I8088_IMR = $21;
     ASyncBasePort      : Array[1..2] of Word = ($3F8,$2F8);
     ASyncIRQ           : Array[1..2] of Word = (4,3);

Var
   Buffer: Array[0..Buffer_Max,1..2] of Char;
   Overflow: Array[1..2] of Boolean;
   Buffer_Count, Buffer_Head, Buffer_Tail: Array[1..2] of Word;


Procedure DisableInterrupts; Inline($FA {CLI});
Procedure EnableInterrupts;  Inline($FB {STI});

Constructor ASyncPort.Init;
Begin
     IsPortOpen := False;
End;

Destructor ASyncPort.Done;
Begin
     ClosePort;
End;

Procedure ASyncPort.ClosePort;
Var
   I, M : Integer;
Begin
  If IsPortOpen Then
  Begin
       DisableInterrupts;

       I := Port[I8088_IMR];
       M := 1 shl IRQ;

       Port[I8088_IMR] := I or M;
       Port[BasePort + 1] := 0;

       EnableInterrupts;

       SetIntVec(IRQ + 8,OriginalVector);
       IsPortOpen := FALSE
  End;
End;

Procedure Com1Isr; Interrupt;
Var
   C : Char;
Begin
     EnableInterrupts;

     If Buffer_Count[1] < Buffer_Max Then
     Begin
          C := Chr(Port[ASyncBasePort[1]]);
          Begin
               Buffer[Buffer_Head[1],1] := C;
               If Buffer_Head[1] < Buffer_Max Then Inc(Buffer_Head[1]) else
                                                   Buffer_Head[1] := 0;
               Inc(Buffer_Count[1]);
          End;
     End Else Overflow[1] := True;

     DisableInterrupts;
     Port[$20] := $20;
End;

Procedure Com2Isr; Interrupt;
Var
   C : Char;
Begin
     EnableInterrupts;

     If Buffer_Count[2] < Buffer_Max Then
     Begin
          C := Chr(Port[ASyncBasePort[2]]);
          Begin
               Buffer[Buffer_Head[2],2] := C;
               If Buffer_Head[2] < Buffer_Max Then Inc(Buffer_Head[2]) else
                                                   Buffer_Head[2] := 0;
               Inc(Buffer_Count[2]);
          End;
     End Else Overflow[2] := True;

     DisableInterrupts;
     Port[$20] := $20;
End;

Function ASyncPort.OpenPort;
Var
   I, M: Integer;
   B: Byte;
Begin
     If IsPortOpen Then ClosePort;

     ComPort := ThePort;
     BasePort := AsyncBasePort[ComPort];
     IRQ  := AsyncIRQ[ComPort];

     If (Port[BasePort + 2] And $F8) <> 0 Then OpenPort := False Else
     Begin
          Port[BasePort + 3] := $03;
          GetIntVec(IRQ + 8, OriginalVector);
          Case ComPort of
               1: SetIntVec(IRQ + 8, @Com1Isr);
               2: SetIntVec(IRQ + 8, @Com2Isr);
          End;

          DisableInterrupts;
          Port[BasePort + 3] := Port[BasePort + 3] And $7F;
          I := Port[BasePort + 5];
          I := Port[BasePort];
          I := Port[I8088_IMR];
          M := (1 shl IRQ) Xor $00FF;
          Port[I8088_IMR] := I And M;
          Port[BasePort + 1] := $01;
          I := Port[BasePort + 4];
          Port[BasePort + 4] := I OR $08;
          EnableInterrupts;

          B := Port[3+BasePort] OR 128;
          Port[3+BasePort]:= B;
          Port[BasePort]  := lo(trunc(115200.0/BaudRate));
          Port[1+BasePort]:= hi(trunc(115200.0/BaudRate));
          Port[3+BasePort]:= B AND 127;

          IsPortOpen := True;
          OpenPort := True;
     End;
End;

Function ASyncPort.ComAvail;
Begin
     ComAvail := (Buffer_Count[ComPort]<>0);
End;

Function ASyncPort.GetCh;
Begin
     GetCh := Buffer[Buffer_Tail[ComPort],ComPort];
     Inc(Buffer_Tail[ComPort]);
     If Buffer_Tail[ComPort] > Buffer_Max then
        Buffer_Tail[ComPort] := 0;
     Dec(Buffer_Count[ComPort]);
End;

Procedure ASyncPort.PutCh;
Begin
     Port[BasePort + 4] := $0B;
     While (Port[BasePort + 6] And $10) = 0 Do;
     While (Port[BasePort + 5] And $20) = 0 Do;
     DisableInterrupts;
     Port[BasePort] := Ord(C);
     EnableInterrupts;
End;

Procedure ASyncPort.HangUp;
Begin
     Port[BasePort+4] := $00;
     Delay(1000);
     Port[BasePort+4] := $03;
End;

Function ASyncPort.Carrier;
Var
   B: Boolean;
   W: Word;
Begin
     W := 0;
     B := True;
     While (W<500) and B do
     Begin
          Inc(W);
          B := (Port[BasePort+6] and $80) <> $80;
     End;
     Carrier := Not(B);
End;

Begin
     OverFlow[1] := False;
     Buffer_Head[1] := 0;
     Buffer_Tail[1] := 0;
     Buffer_Count[1]:= 0;
     OverFlow[2] := False;
     Buffer_Head[2] := 0;
     Buffer_Tail[2] := 0;
     Buffer_Count[2]:= 0;
End.