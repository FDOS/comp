;	COMP	Replacement for the messy-dos command of the same name.

;	To assemble (using nasm 0.98.36):
;		nasm comp.asm -o comp.com -O 2

;	Usage:	comp [/#] file1 [file2]
;		where file1 and file2 may be directories or may contain
;		wildcards (but not both).  The default for file2 is the current
;		directory on the current disk.  The switch gives the maximum
;		number of errors to report per file, no limit if #=0.  Default
;		is 0 if file1 refers to a single file, 10 otherwise.
;		Also "comp /?" prints a help message and quits.
;		The '/' in the switch refers to the switch character.

;	Author:  Paul Vojta

;	======================================================================
;
;	Copyright (c) 2003  Paul Vojta
;
;	Permission is hereby granted, free of charge, to any person obtaining a
;	copy of this software and associated documentation files (the
;	"Software"), to deal in the Software without restriction, including
;	without limitation the rights to use, copy, modify, merge, publish,
;	distribute, sublicense, and/or sell copies of the Software, and to
;	permit persons to whom the Software is furnished to do so, subject to
;	the following conditions:
;
;	The above copyright notice and this permission notice shall be included
;	in all copies or substantial portions of the Software.
;
;	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
;	OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;	MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
;	IN NO EVENT SHALL PAUL VOJTA OR CONTRIBUTORS BE LIABLE FOR ANY CLAIM,
;	DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
;	OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR
;	THE USE OR OTHER DEALINGS IN THE SOFTWARE.
;
;	======================================================================

;	Revision history:
;	    1.03 [6 August 2003]    Converted to nasm; added help message.
;	    1.04 [21 October 2006]  Added copyright message.

	org	100h
	cpu	8086

stdout	equ	1
stderr	equ	2

CR	equ	13
LF	equ	10
TAB	equ	9

	section	.data

;	Memory locations in the program segment prefix

fn1	equ	5ch		;filename portion of string 1
str2	equ	5eh		;string 2
fn2	equ	60h
pat2	equ	62h		;pattern for filling in wild cards in filename 2
str1	equ	70h

slash	db	'/'
msg1	db	'Illegal switch.',CR,LF,0
msg2	db	'Invalid number of parameters.',CR,LF,0
msg3	db	'File not found.',CR,LF,0
msg4	db	'Access denied.',CR,LF,0
msg5	db	'I/O error.',CR,LF,0
fil	db	'File ',0
hyph	db	'--',0
hdr	db	CR,LF,'Byte    File 1  File 2',CR,LF,0
lyne	db	'xxxx    aa      bb "x"',CR,LF,0
xs	db	'nnnn excess bytes on file x.',CR,LF,0
nerrs	db	' error(s).',CR,LF,0
ok	db	'Files compare OK.'	;(continues...)
crlf	db	CR,LF,0
atleast	db	'At least ',0

okmsg	dw	ok
maxerrs	dw	0
maxerrset db	0

end1:

helpmsg	db	'Compare files.',CR,LF,CR,LF
	db	'Syntax:  COMP ['
switchar1 db	'/options] <file1> [file2]',CR,LF,CR,LF
	db	TAB,'where <file1> and [file2] are file names (possibly with '
	db	'wild cards)',CR,LF
	db	TAB,'or directory names.  If [file2] is omitted, the current '
	db	'directory',CR,LF
	db	TAB,'is assumed.',CR,LF,CR,LF
	db	'Options:  ?',TAB,'Display this message and quit.',CR,LF
	db	TAB,'  <#>',TAB,'Do not print more than # errors per file.  '
	db	'If #=0, do not limit',CR,LF
	db	TAB,TAB,'the number of errors.  Default is 0 if <file1> refers '
	db	'to a',CR,LF
	db	TAB,TAB,'single file; 10 if more than one file.',CR,LF,0

area43	equ	end1
attr	equ	21		;offset in area43
flname	equ	30		;ditto

errcnt	equ	word end1+43
bufno	equ	word end1+45
len1	equ	word end1+47
len2	equ	word end1+49
buflen	equ	word end1+51
atlflag	equ	byte end1+53
buf	equ	end1+54

;	Begin.  Set disk transfer address and slash.

	section	.text

	mov	ah,1ah		;set DTA
	mov	dx,area43
	int	21h
	mov	ax,3700h	;get switch character
	int	21h
	mov	byte [switchar1],dl
	cmp	dl,'/'
	jne	f1
	mov	byte [slash],'\'
f1:	cld

;	Handle switches

	mov	di,81h
	mov	ch,0
	mov	cl,[di-1]

f2:	jcxz	f9		;if end of string
	mov	al,dl		;switch character
	repnz	scasb
	jne	f9		;if done searching
	cmp	al,'/'
	je	f3		;if slash, don't require preceding white space
	mov	al,[di-2]
	cmp	al,' '
	je	f3		;if space
	cmp	al,TAB
	jne	f2		;if not tab

;	Interpret switch (must be numeric argument or `/?')

f3:	cmp	byte [di],'?'
	je	f8		;if `/?'
	xor	bx,bx		;value of the argument
	push	cx
	mov	cx,10
	mov	si,di
f4:	mov	byte [si-1],' '	;erase the previous character
	lodsb
	sub	al,'0'
	cmp	al,9	
	ja	f5		;if not digit
	xchg	ax,bx
	mul	cx
	mov	bh,0
	add	bx,ax
	jmp	f4		;loop back for more

f5:	mov	[maxerrs],bx	;save argument
	mov	byte [maxerrset],1;set flag indicating we've done this
	pop	cx
	cmp	al,' '-'0'
	je	f2		;if ended with space
	cmp	al,TAB-'0'
	je	f2		;if ended with tab
	cmp	al,CR-'0'
	je	f2		;if ended with CR
	mov	dx,msg1		;illegal switch
	jmp	short f7	;error quit
f6:	mov	dx,msg2		;insufficient parameters
f7:	jmp	errend

;	Print help message and quit.

f8:	mov	dx,helpmsg
	call	print
	int	20h		;quit

;	Compute buffer size.

f9:	mov	ax,sp
	sub	ax,buf+100h
	shr	ax,1
	mov	al,0
	mov	word [buflen],ax

;	Start scanning parameters.

	mov	si,81h
f10:	lodsb			;skip spaces
	cmp	al,' '
	je	f10		;if space
	cmp	al,TAB
	je	f10		;if tab
	dec	si		;get first parameter
	mov	di,str1
	call	getparm
	jz	f6		;if no parameter present
	pushf
	push	word [area43+attr]
	mov	[fn1],bx	;beginning of file name 1
	lea	di,[bx+14]
	mov	[str2],di	;start of second string
	call	getparm
	mov	[fn2],bx
	mov	si,bx		;set up pat2
	mov	di,pat2
	mov	cx,7
	rep	movsw
	pop	word [area43+attr]
	popf
	jns	f11		;if wild cards
	call	doit
	jmp	short quit

;	Compare multiple files.

f11:	cmp	byte [maxerrset],0
	jnz	f12		;if maxerrs given
	mov	word [maxerrs],10 ;default = 10
f12:	mov	dx,str1
	mov	cx,1
	mov	ah,4eh		;find first file
	int	21h
	jc	f14		;if not found
	mov	word [okmsg],crlf

f13:	mov	si,area43+flname
	mov	di,[fn1]
	mov	cx,7
	rep	movsw
	mov	dx,str1
	call	print
	call	doit
	mov	ah,4fh		;find next file
	int	21h
	jnc	f13

quit:	mov	ax,4c00h
	int	21h

f14:	mov	dx,msg3		;file not found
	jmp	errend

;	GETPARM	Get next parameter.  Upon entry, si points to the next character
;		in the command string and di points where to put it.  On exit,
;		si points to the next+1 character in the command line, di points
;		to the end of the parameter, and bx points to the beginning of
;		the filename part of the string.  AH=0 if no parameter, 1 if
;		wild cards are present, and 80h if it is a file.  Flags are set
;		according to AH.

getparm:mov	[str2],di

	lodsb		;skip separators
	cmp	al,' '
	je	getparm
	cmp	al,TAB
	je	getparm
	cmp	al,CR
	mov	ah,0
	je	gp7		;if C/R

gp1:	stosb		;copy until separator
	lodsb
	cmp	al,' '		;check for separator
	je	gp2
	cmp	al,TAB
	je	gp2
	cmp	al,CR
	jne	gp1
	dec	si

;	Process the parameter.

gp2:	mov	byte [di],0
	mov	bx,di
	mov	ah,81h		;scan for start of file name

gp3:	dec	bx
	cmp	bx,[str2]
	jl	gp5		;if past beginning
	mov	al,[bx]
	cmp	al,[slash]
	je	gp6		;if '\' or '/'
	cmp	al,'?'		;check for wild cards
	je	gp4
	cmp	al,'*'
	jne	gp3
gp4:	and	ah,7fh		;clear no-wild bit
	jmp	gp3

gp5:	cmp	byte [bx+2],':'	;no dir. given; remove drive letter
	jne	gp6
	inc	bx
	inc	bx

gp6:	inc	bx
	or	ah,ah
	jns	gp8		;if wild cards
	cmp	bx,di
	mov	ah,1
	je	gp7		;if no file name
	mov	ax,4300h	;see if directory
	mov	dx,[str2]
	int	21h
	mov	ah,80h
	jc	gp8		;if not found
	test	cl,10h		;test attribute for directory
	jz	gp8		;if file

;	It's a directory.

	mov	al,[slash]
	stosb
	mov	ah,1

gp7:	push	ax
	mov	bx,di		;add "*.*"
	mov	ax,'*.'
	stosw
	stosb
	mov	byte [di],0
	pop	ax

;	Return.

gp8:	or	ah,ah		;set flags
	ret

;	DOIT	Do it.  Str1, str2, and pat2 are assumed to be set up.

doit:	mov	si,pat2
	mov	bx,[fn1]
	mov	di,[fn2]
	mov	cx,8
	call	dopart		;translate wild cards for main part of file name
	dec	si
d1:	lodsb			;skip to file extension
	or	al,al
	jz	d4		;if end of file
	cmp	al,'.'
	jne	d1
	stosb			;store '.'
d2:	mov	al,byte [bx]	;skip to extension in first file name
	cmp	al,0
	jz	d3
	inc	bx
	cmp	al,'.'
	jne	d2
d3:	mov	cl,3		;translate wild cards for file extension
	call	dopart

;	Set up files.

d4:	mov	byte [di],0	;store terminating zero
	mov	dx,str1		;open file
	mov	ax,3d00h
	int	21h
	jc	err		;if error
	mov	si,ax
	mov	ax,3d00h	;open file
	mov	dx,[str2]
	int	21h
	jnc	d5		;if no error
	cmp	ax,2
	jne	err1		;if not file-not-found
	call	hyphens
	mov	dx,fil
	call	print
	mov	dx,[str2]
	call	print
	mov	dx,msg3+4	;' not found.'
	call	print
	mov	ah,3eh		;close other file
	mov	bx,si
	int	21h
	jc	err
	ret

d5:	mov	bx,ax
	mov	word [bufno],0
	mov	word [errcnt],0
	mov	byte [atlflag],0

;	Loop for comparing.  si, bx = file handles.

d6:	mov	cx,[buflen]	;read from file 1
	mov	dx,buf
	xchg	bx,si
	mov	ah,3fh
	int	21h
	jc	err		;if error
	mov	word [len1],ax
	push	bx
	mov	bx,si
	mov	si,dx
	add	dx,cx		;read from file 2
	mov	ah,3fh
	int	21h
	jc	err
	mov	word [len2],ax
	push	bx
	mov	di,dx
	cmp	ax,[len1]
	jle	d7		;find minimum length
	mov	ax,[len1]
d7:	cmp	ax,[buflen]	;whether this is the last
	pushf

;	Begin loop over mini-buffers

d8:	mov	cx,256
	cmp	ax,cx
	jae	d9
	mov	cx,ax
d9:	sub	ax,cx
	push	ax

;	Do comparison.

d10:	repz	cmpsb
	je	d15		;if buffers equal

;	Print error message.

	push	cx
	push	di
	cmp	word [errcnt],0
	jne	d11		;if not the first error
	mov	dx,hdr		;print header
	call	print
d11:	call	inccount	;increment error count
	mov	di,lyne
	mov	dx,di
	mov	ax,[bufno]
	cmp	ah,0
	je	d12		;if not a huge file
	push	ax
	mov	al,ah
	call	hex
	stosw
	pop	ax
d12:	call	hex
	stosw
	mov	ax,si
	sub	ax,buf+1
	call	hex
	stosw
	pop	bx		;old di
	mov	al,[si-1]	;convert data bytes to hex
	mov	di,lyne+6
	call	dumpbyte
	mov	al,[bx-1]
	call	dumpbyte

;	Trim spaces from input line.

d13:	dec	di
	cmp	byte [di],' '
	je	d13		;if space
	inc	di
	mov	ax,CR+256*LF
	stosw
	mov	al,0
	stosb
	mov	di,bx
	call	print		;print the line
	pop	cx
	mov	ax,[errcnt]
	cmp	ax,[maxerrs]
	jne	d14		;if within limits
	mov	byte [atlflag],1 ;set flag to print "At least"
	pop	ax
	popf
	pop	bx
	pop	si
	jmp	short d18

d14:	or	cx,cx
	jnz	d10		;if more comparisons to do

d15:	inc	word [bufno]	;end mini-buffer
	pop	ax
	or	ax,ax
	jnz	d8		;if more in this buffer
	popf
	pop	bx		;get file handles
	pop	si
	je	d6		;if not eof yet
	mov	ax,[len2]
	sub	ax,[len1]
	mov	cl,'2'
	jg	d16		;if excess bytes on file 2
	je	d18		;if exact match
	dec	cx
	xchg	bx,si
	neg	ax

;	Excess bytes on some file.

d16:	mov	byte [xs+26],cl
	mov	[len1],ax
	mov	cx,[buflen]
	mov	dx,buf

d17:	mov	ah,3fh		;read excess bytes
	int	21h
	jc	err
	add	[len1],ax
	cmp	ax,cx
	je	d17		;if more to go

	mov	al,[len1+1]	;form and print excess-bytes message
	call	hex
	mov	word [xs],ax
	mov	al,byte [len1]
	call	hex
	mov	word [xs+2],ax
	push	bx
	mov	dx,xs
	call	print
	pop	bx
	call	inccount	;increment error count
	
;	Close files and print error count.

d18:	mov	ah,3eh		;close file
	int	21h
	jc	err
	mov	ah,3eh
	xchg	bx,si
	int	21h
	jc	err

	mov	dx,[okmsg]	;get OK-message address
	mov	ax,[errcnt]
	or	ax,ax
	jz	d22		;if no errors
	cmp	byte [atlflag],0
	jz	d19		;if we don't need to print "at least"
	push	ax
	mov	dx,atleast	;print "at least"
	call	print
	pop	ax
d19:	mov	bx,10
	xor	cx,cx

d20:	xor	dx,dx		;convert to decimal
	div	bx
	add	dl,'0'
	push	dx
	inc	cx
	or	ax,ax
	jnz	d20		;if more digits
	mov	ah,2

d21:	pop	dx		;print the number
	int	21h
	loop	d21
	mov	dx,nerrs

;	Common ending routine.

d22:	jmp	short print	;call print and return

;	Process errors.

err1:	cmp	ax,5
	jne	err		;if not invalid path
	call	hyphens
	mov	dx,msg4
	jmp	short errend

err:	mov	dx,msg3		;file not found
	cmp	ax,2
	je	errend		;if file not found
	call	hyphens
	mov	dx,msg5		;I/O error
;	jmp	short errend	;(control falls through)

;	Ending stuff.

errend:	mov	bx,stderr
	call	print0
	mov	ax,4c01h
	int	21h

;	HYPHENS	Print hyphens (but only if this is a multiple comp).
;	PRINT	Print the line at (DX).  Destroys AX,CX.
;	PRINT0	Same as above, but also requires BX = output handle.

hyphens:mov	dx,hyph
print:	mov	bx,stdout
print0:	push	di
	mov	di,dx
	mov	cx,-1
	mov	al,0		;find length
	repnz	scasb
	not	cx
	dec	cx
	mov	ah,40h
	int	21h
	pop	di
	ret

;	DOPART	Copy string from [si] to [di], changing wild cards to those
;		present in [bx].  This copies up to CX characters.

dopart:	lodsb
	cmp	al,'.'
	je	dp5		;if end of this part
	cmp	al,0
	je	dp5		;if end
	cmp	al,'*'
	jne	dp1
	dec	si
	mov	al,'?'
dp1:	cmp	al,'?'
	jne	dp2		;if not wild card
	mov	al,[bx]
	cmp	al,'.'
	je	dp3
	cmp	al,0
	je	dp3
dp2:	stosb
dp3:	cmp	byte [bx],'.'	;advance [bx], but not past '.' or end of string
	je	dp4
	cmp	byte [bx],0
	je	dp4
	inc	bx
dp4:	loop	dopart
	inc	si
dp5:	ret

;	DUMPBYTE Print a byte in hexadecimal and then as a character.

dumpbyte:push	ax
	mov	ax,'  '
	stosw
	pop	ax
	push	ax
	call	hex
	stosw
	mov	al,' '
	stosb
	pop	ax
	cmp	al,0
	je	db2		;if null character
	cmp	al,' '
	jb	db1		;if control character
	cmp	al,127
	ja	db2		;if not a character
	mov	ah,al
	mov	al,"'"		;save normal character
	stosw
	stosb
	ret

db1:	add	al,'A'-1	;control character
	mov	ah,al
	mov	al,'^'
	jmp	db3

db2:	mov	ax,'  '		;just put spaces
db3:	stosw
	mov	al,' '
	stosb
	ret

;	HEX	Convert a byte to hexadecimal.  Destroys (CL).

hex:	mov	ah,0
	mov	cl,4
	shl	ax,cl
	shr	al,cl
	add	al,90h		;these four instructions change to ascii hex
	daa
	adc	al,40h
	daa
	xchg	al,ah
	add	al,90h
	daa
	adc	al,40h
	daa
	ret

;	INCCOUNT - Increment the variable "errcnt" (unless it equals 65535).

inccount: inc	word [errcnt]
	jnz	ic1		;if we're OK
	dec	word [errcnt]
	mov	byte [atlflag],1 ;set flag to print "At least"
ic1:	ret

	end
