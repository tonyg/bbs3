title   Tasker Kernel

; INT 60h,AH=0 Yield,AH=1 Fork,AH=2 Suicide,AH=3 GetData
;         AH=4 SetData

; Kernel for Multitasking MTASK.TPU. Version 1.02
; Copyright (C) Tony Garnock-Jones, July 1992

.model  medium
.code
public  _Int60h,_InitTasking

ProcRec struc                           ;Structure for storing each processes
stackseg        dw      ?               ;data and stack pointers.
stackofs        dw      ?
state           db      ?
ProcRec ends

_Int60h proc    far                     ;The actual interrupt

        jmp     codestart

thisp           dw      ?               ;This is the CURRENT PROCESS I.D.
livecount       db      ?               ;This is how many processes are active
error           db      ?               ;This is 0 if no error, 1 if error

codestart:
        push    bp                      ;Set up stack frame: Not really needed
        mov     bp,sp

        push    ds
        push    es
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        pushf                           ;Save all important registers
;===========================================TASKSWITCH call
        cmp     ah,0
        jne     noswaptask
        cmp     livecount,1             ;Are there more than 1 active process?
        jg      swaptasks               ;Yes, then go to SwapTasks

        mov     ax,5                    ;No, then is _this_ process dead?
        mul     thisp
        mov     di,si
        add     di,ax
        cmp     [di].state,0
        je      swaptasks               ;Yes, then go to SwapTasks

        mov     error,0                 ;Clear the error flag
        jmp     endint                  ;Return to caller
swaptasks:
        mov     ax,5
        mul     thisp                   ;Find address in array of processes
                                        ;5 is the size of one ProcRec.
        mov     di,si
        add     di,ax
        mov     [di].stackseg,ss        
        mov     [di].stackofs,sp        ;Save the current SS:SP
notalive:
        inc     thisp                   ;Select next process
        cmp     thisp,20                ;Is it out of bounds?
        jle     notovermax              ;No, then goto NotOverMax
        mov     thisp,0                 ;Yes, then select process 0.
notovermax:
        mov     ax,5
        mul     thisp                   ;Find new process address.
        mov     di,si
        add     di,ax
        cmp     [di].state,0            ;Is the new process alive?
        je      notalive                ;No, then back up to NotAlive
        mov     ss,[di].stackseg
        mov     sp,[di].stackofs        ;Select new SS:SP
        mov     error,0                 ;Clear error flag
        jmp     endint                  ;Return to Caller
;===========================================FORK call
noswaptask:
        cmp     ah,1
        jne     noaddtask
        inc     livecount
        mov     ax,5
        mul     dx                      ;Get address of new process record
        mov     di,si
        add     di,ax
        mov     [di].stackseg,es        ;Set the new processes stack to
        mov     [di].stackofs,bx        ;the stack at ES:BX
        add     [di].stackofs,sp        ;Make sure the SP's match up.
        mov     [di].state,1            ;Bring it to life
        mov     cx,4000h
        push    ds
        push    si
        push    di
        push    ss
        pop     ds
        mov     si,0
        mov     di,bx
        rep     movsb                   ;Copy the old stack -> new stack.
        pop     di
        pop     si
        pop     ds
        mov     error,0                 ;Clear the error flag
        jmp     endint                  ;Return to Caller
;===========================================SUICIDE call
noaddtask:
        cmp     ah,2
        jne     nosuicide
        mov     ax,5
        mul     thisp                   ;Get address of current process record
        mov     di,si
        add     di,ax
        mov     [di].state,0            ;Kill it
        dec     livecount
        mov     error,0                 ;Clear error flag
        jmp     endint                  ;Return to Caller
;===========================================GETDATA call
nosuicide:
        cmp     ah,3                    ;Well, seeing as all functions return
        jne     nogetdata               ;Data anyway, I might as well make one
                                        ;which returned data but didnt actually
                                        ;do anything
;===========================================SETDATA call
nogetdata:
        cmp     ah,4
        jne     endint
        mov     thisp,cx                ;Call with CX=ThisP..BE CAREFUL!!
        mov     livecount,dl            ;Call with DL=LiveCount
        mov     error,0                 ;Clear error flag
        jmp     endint                  ;Return to Caller

endint: popf
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        pop     es
        pop     ds

        mov     ax,thisp
        mov     dl,livecount
        mov     dh,error                ;Return the data in AX,BX and DX

        pop     bp                      ;Restore stack frame
        iret                            ;Return!

_Int60h endp

_InitTasking    proc    far

        mov     thisp,0
        mov     livecount,1             ;Set up vars before use
        retf

_InitTasking    endp

        end

