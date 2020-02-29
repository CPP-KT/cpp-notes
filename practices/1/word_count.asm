                section         .rodata ; this section represents Read-Only DATA
                ; db is used to declare initialized data in output file
read_error_msg: db              "read failure", 0x0a ; string to output when read failure occurres
                ; equ defines constant (aka "define" in C++)
read_error_len: equ             13 ; length of string above
sys_exit:       equ             60 ; code of sys_exit syscall
buff_size:      equ             128 ; size of buffer for this runtime

                section         .text ; this section represents code for our program
                global          _start ; Defines this section as entering point of our program for outer

_start:
                xor             rbx, rbx; RBX will store the result of our counting
                mov             r12, 1 ; R12 will indicate if last symbol was whitespace

                sub             rsp, buff_size ; We free space on the stack for buffer in which we will read
                mov             rsi, rsp ; RSI for sys_read points at beginning of the array of chars, where we store the result

read_again:
                xor             rax, rax ; RAX = 0 calls sys_read
                xor             rdi, rdi ; RDI for sys_read is file descriptor, we need it to be standard input
                mov             rdx, buff_size ; RDX for sys_read is count of bytes to read
                syscall

                test            rax, rax ; performing test to set flags accordingly to RAX value
                js              read_error ; if RAX is negative, then an input error occurred
                jz              quit ; if RAX is zero, then input has ended, finish the program

                xor             rcx, rcx ; move rcx to zero (rcx is position in buffer which we read from)

                jmp             check_char


skip_whitespace: ; read check_char first
                mov             r12, 1 ; we set R12 to one to indicate that current symbol is whitespace
                inc             rcx ; and move to the next symbol

check_char:
                cmp             rcx, rax ; if we reached end of input,
                je              read_again ; try to read again
                ; all these lines are serving one purpose --- to check if character with index RSI + RCX is whitespace
                ; i will try to simplify this check
                ; movzx moves value into specified register and extends it with zeros
                movzx           rdx, byte [rsi + rcx]
                cmp             rdx, 9
                je              skip_whitespace
                cmp             rdx, 10
                je              skip_whitespace
                cmp             rdx, 11
                je              skip_whitespace
                cmp             rdx, 12
                je              skip_whitespace
                cmp             rdx, 13
                je              skip_whitespace
                cmp             rdx, 32
                je              skip_whitespace
                ; this nightmare finally ended. If we came here, current symbol is not whitespace
                add             rbx, r12 ; if last symbol is whitespace, we add 1 to result
                xor             r12, r12 ; then we make R12 zero, because current symbol is not whitespace
                inc             rcx ; we move to the next symbol by incrementing pointer RCX
                jmp             check_char ; and repeat


quit:
                mov             rax, rbx ; pass answer to read_int function
                call            print_int ; print answer

                mov             rax, sys_exit ; RAX = sys_exit calls (wow) sys_exit
                xor             rdi, rdi ; RDI for sys_exit is error code (and everything's fine, thus its 0)
                syscall

; TODO
print_int:
                mov             rsi, rsp
                mov             rbx, 10

                dec             rsi
                mov             byte [rsi], 0x0a
next_char:
                xor             edx, edx
                div             ebx
                add             dl, '0'
                dec             rsi
                mov             [rsi], dl
                test            rax, rax
                jnz             next_char

                mov             eax, 1
                mov             edi, 1
                mov             rdx, rsp
                sub             rdx, rsi
                syscall

                ret

read_error:
                mov             r12, rax ; Save error code for later
                mov             rax, 1 ; RAX = 1 calls sys_write
                mov             rdi, 2 ; RDI for sys_write is file descriptor, we need it to be standard error
                mov             rsi, read_error_msg ; RSI for sys_write is char buffer to output
                mov             rdx, read_error_len ; RDI for sys_write is count of characters to output
                syscall

                mov             rax, sys_exit ; RAX = sys_exit calls (wow) sys_exit
                mov             rdi, r12 ; RDI for sys_exit is error code
                syscall

