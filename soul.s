.org 0x0
.section .iv, "a"

_start:

interrupt_vector:

	b RESET_HANDLER
.org 0x08
	b	SVC_HANDLER
.org 0x18
	b IRQ_HANDLER

.text

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ Constantes
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

    .set TIME_SZ,		         100

    @ Enderecos dos registradores do GPT
  	.set GPT_BASE,	            0x53FA0000
  	.set GPT_PR,		        0x04
  	.set GPT_IR,                0x0C
  	.set GPT_OCR1, 	            0x10

    @ Enderecos dos registradores do TZIC
	.set TZIC_BASE,             0x0FFFC000
	.set TZIC_INTCTRL,          0x0
	.set TZIC_INTSEC1,          0x84
	.set TZIC_ENSET1,           0x104
	.set TZIC_PRIOMASK,         0xC
	.set TZIC_PRIORITY9,        0x424

    @ Enderecos dos registradores do GPIO
	.set GPIO_BASE,             0x53F84000
    .set GPIO_GDIR,             0x04
    .set GPIO_PSR,              0x08

    .set MAX_ALARMS,			8
    .set MAX_CALLBACKS,         8


@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ Configuracoes da iniciais do sistema
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

RESET_HANDLER:
	ldr r0, =interrupt_vector
	mcr p15, 0, r0, c12, c0, 0

@ Configura o GPT
SET_GPT:

	ldr r0, =GPT_BASE
	mov r1, #0x00000041
	str r1, [r0]

	mov r1, #0
    str r1, [r0, #GPT_PR]

	mov r1, #TIME_SZ
	str r1, [r0, #GPT_OCR1]

	mov r1, #1
	str r1, [r0, #GPT_IR]

@ Configura o TZIC
SET_TZIC:

	@ Liga o controlador de interrupcoes
	@ R1 <= TZIC_BASE

  ldr	r1, =TZIC_BASE

  @ Configura interrupcao 39 do GPT como nao segura
    mov	r0, #(1 << 7)
    str	r0, [r1, #TZIC_INTSEC1]

    @ Habilita interrupcao 39 (GPT)
    @ reg1 bit 7 (gpt)

    mov	r0, #(1 << 7)
    str	r0, [r1, #TZIC_ENSET1]

    @ Configure interrupt39 priority as 1
    @ reg9, byte 3

    ldr r0, [r1, #TZIC_PRIORITY9]
    bic r0, r0, #0xFF000000
    mov r2, #1
    orr r0, r0, r2, lsl #24
    str r0, [r1, #TZIC_PRIORITY9]

    @ Configure PRIOMASK as 0
    eor r0, r0, r0
    str r0, [r1, #TZIC_PRIOMASK]

    @ Habilita o controlador de interrupcoes
    mov	r0, #1
    str	r0, [r1, #TZIC_INTCTRL]

    @ Instrucao msr - habilita interrupcoes
    msr  CPSR_c, #0x13       @ Modo supervisor, IRQ/FIQ habilitados

@ Configura o GPIO
SET_GPIO:

	@ Define o endereco base do GPIO no r1
	ldr r1, =GPIO_BASE
	mov r0, #0
	str r0, [r1]

	@ Configura o GDIR
	ldr r0, =0xFFFC003E
	str r0, [r1, #GPIO_GDIR]


	ldr r2, =system_time
	mov r0, #0
	str r0, [r2]


	msr CPSR_c, #0x13
	ldr SP, =0x77805000

	msr CPSR_c, #0x12
	ldr SP, =0x77806000

	msr CPSR_c, #0x1F
	ldr SP, =0x77808000

	ldr r0, =0x77802000
	msr CPSR_c, #0x10
	bx r0


@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ Tratamentos de interupcoes
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

@ Direciona cada syscall para o tratamento correto
SVC_HANDLER:
	msr CPSR_c, 0xD3
	cmp r7, #16
	beq sys_read_sonar

	cmp r7, #17
	beq sys_register_proximity_callback

	cmp r7, #18
	beq sys_set_motor_speed

	cmp r7, #19
	beq sys_set_motors_speed

	cmp r7, #20
	beq sys_get_time

	cmp r7, #21
	beq sys_set_time

	cmp r7, #22
	beq sys_set_alarm

	cmp r7, #23
	beq modo_user

	cmp r7, #50
	beq	change_mode_proximity_callback

	movs pc, lr

@ Trata as interrupcoes de hardware
IRQ_HANDLER:
	stmfd sp!, {r0-r10, lr}
	ldr r0, =0X53FA0008
	mov r1, #0x1
	str r1, [r0]

	ldr r2, =system_time
	ldr r1, [r2]
	add r1,r1,#1
	str r1, [r2]

	ldr r3, =ta_rolando_um_callback
	ldr r3, [r3]
	cmp r3, #1
	beq pula_fora


	@---------Tratamento das interrupcoes do proximity callback---------@
	irq_register_proximity_callback_handler:

	  ldr r4, =0 @ Contador de controle de laco
	  ldr r2, =NUM_CALLBACKS
	  ldr r5, [r2]

    @ Verifica se alguma callback deve ser feita
	verifica_callbacks:

		@ Verifica se tem algo no vetor de callbacks ...
		cmp r5, #0
		beq fim_proximity_callback_handler @ ... se nao tiver sai da funcao
		ldr r1, =vetor_proximity_callback
		@ r0 recebe o id do sonar se houver uma callback nessa posicao do vetor
		@ e recebe 16 se nao houver
		ldr r0, [r1, r4]

		@ Verifica se tem uma callback nessa posicao do vetor ...
		cmp r0, #16

		bne tem_callback @ ... se houver vai trata-la ...
		add r4, r4, #12 @ ... se houver soma o contador de controle de laco ...
		bal verifica_callbacks @ ... e volta para o inicio do laco

	tem_callback:

		@ Dimiui em 1 o numero de callbacks a serem verificadas
		sub r5, r5, #1

		@ Verifica a distancia marcada pelo sonar
		@ Salva o estado
		stmfd sp!, {r1-r11, lr}

		@ Indica que uma callback esta acontecendo
		ldr r1, =ta_rolando_um_callback
    mov r2, #1
    str r2, [r1]

	    @ Muda para o modo system para passar o parametro da syscall pela
	    @ pilha do user/system
		msr CPSR_c, #0xDF

        @ Salva o elemento da pilha do user que sera sobreescrito
        sub sp, sp, #4
        ldmfd sp!, {r11}

		@ Empilha o parametro (id do sonar) que deve ser passado como parametro
		stmfd sp!, {r0}

		@ Faz a chamada da syscall para a leitura do sonar
		mov r7, #16
		svc 0x0

        add sp, sp, #4
        stmfd sp!, {r11}
        add sp, sp, #4

		@ Volta para o modo antigo
		msr CPSR_c, #0xD2
		@ Recupera o estado antigo
		ldmfd sp!, {r1-r11, lr}




	    @ Verifica se a distancia lida eh menor que a minima do callback
	    @ Carrega em r1 a distancia minima
    ldr r2, =vetor_proximity_callback
		add r2, r2, #4
		ldr r1, [r2, r4]
    cmp r0, r1 @ ... e a compara com a leitura do sonar


		@ Indica que a callback terminou
		ldrhi r1, =ta_rolando_um_callback
    movhi r2, #0
    strhi r2, [r1]
    addhi r4, r4, #12
    bhi verifica_callbacks

	  @ Como a distancia atual eh menor que a minima, chama a funcao
	  @ Salva o estado
    stmfd sp!, {r0-r11, lr}

		@ Muda para o modo USER e chama a funcao
		ldr r2, =vetor_proximity_callback
		add r2, r2, #8
		ldr r0, [r2, r4]
		msr CPSR_c, #0x10
	  blx r0
	  mov r7, #50
		svc 0x0

    volta_da_syscall_proximity_callback:
		@ Indica que nao tem mais uma callback acontecendo
		ldr r1, =ta_rolando_um_callback
	    ldr r2, =0x0
	    str r2, [r1]

		ldmfd sp!, {r0-r11, lr}

		add r4, r4, #12
	  bal verifica_callbacks

	fim_proximity_callback_handler:

  @---------Tratamento das interrupcoes do proximity callback---------@

	@---------ALARME----------------------------------------------------@
  irq_alarm_callback_handler:
		mov r3, #0
		ldr r4, =num_alarms
		ldr r9, [r4]


	loop_alarme_ativo:
		cmp r9, #0
		beq fim_alarm_handler
		ldr r0, =alarm_vector
		ldr r5, [r0, r3]
		cmp r5, #0
		addeq r3, r3, #8
		beq loop_alarme_ativo

		sub r9, r9, #1

		mov r1, #0
		add r1, r3, #4
		ldr r6, [r0, r1]

		ldr r2, =system_time
		ldr r2, [r2]
		cmp r2, r6
		blt loop_alarme_ativo

		stmfd sp!, {r0-r11, lr}
		ldr r1, =ta_rolando_um_callback
		ldr r2, =0x1
		str r2, [r1]
		msr CPSR_c, #0x10
		blx r5

		mov r7, #23
		svc #0

		loopizinho:
		ldr r1, =ta_rolando_um_callback
		ldr r2, =0x0
		str r2, [r1]
		ldmfd sp!, {r0-r11, lr}
		mov r5, #0
		str r5, [r0, r3]
		ldr r10, [r4]
		sub r10, r10, #1
		str r10, [r4]
		add r3, r3, #8
		@mov r3, #0
		b loop_alarme_ativo

	fim_alarm_handler:
  @---------------------ALARME---------------------------@
		pula_fora:
			ldmfd sp!, {r0-r10, lr}
			sub lr, lr, #4
			movs pc, lr

@--------SYSCALL SONAR----------------------@
sys_read_sonar:

  stmfd sp!, {r1-r11, lr} @ Salva os registradores na pilha

	msr CPSR_c, #0xDF @ Muda para o modo SYSTEM
	ldmfd sp!, {r4} @ Pega o parametro da pilha USER/SYSTEM
  sub sp, sp, #4 @ Volta a pilha ao estado antigo
	msr CPSR_c, #0xD3 @ Volta para o modo SUPERVISOR

	mov r0, #0
	cmp r4, #0
	movlt r0, #-1
	cmp r4, #15
	movgt r0, #-1
	cmp r0, #0
	bne fim
	mov r4, r4, lsl #2
	ldr r5, =0xFFFFFFC1
	ldr r6, =GPIO_BASE
	ldr r8, [r6]
	and r5, r8, r5
	orr r4, r5, r4
	str r4, [r6]
	mov r9, pc
	b delay

	add r4, r4, #2
	str r4, [r6]
	mov r9, pc
	b delay

	sub r4, r4, #2
	str r4, [r6]

	loop_flag:
		mov r9, pc
		b delay
		ldr r8, [r6]
		and r4, r8, #1
		cmp r4, #1
		bne loop_flag

	ldr r5, =0x3FFC0
	and r0, r8, r5
	mov r0, r0, lsr #6
  ldmfd sp!, {r1-r11, lr}
	movs pc, lr

@--------SYSCALL SET_CALLBACK---------------@
sys_register_proximity_callback:

	stmfd sp!, {r1-r11, lr} @ Salva os registradores na pilha

	msr CPSR_c, #0x1F @ Muda para o modo SYSTEM
	ldmfd sp!, {r1, r2, r3} @ Pega os parametros da pilha do USER/SYSTEM
    sub sp, sp, #12 @ Volta a pilha para o estado antigo
	msr CPSR_c, #0x13 @ Volta para o modo SUPERVISOR

	@ Verifica se o id do sonar eh valido
	cmp r1, #15
	bhi retorna_menos_dois
	cmp r1, #0
	blo retorna_menos_dois

	@ Verifica se o numero maximo de callbacks ja chegou no limite
	ldr r4, =NUM_CALLBACKS
	ldr r4, [r4]
	cmp r4, #MAX_CALLBACKS
	bhs retorna_menos_um

	@Define os valores iniciais
	ldr r4, =NUM_CALLBACKS @Endereco do num de callbacks
	mov r5, #0  @Contador de posicao
	ldr r6, =vetor_proximity_callback @Endereco inicial do struct de callback

	@Loop da busca
	loop_busca_callback:
		ldr r7, [r6, r5] @Coloca o valor do id do sonar no r7
		cmp r7, #16 @Verifica se está com o valor inicializado
		addne r5, #12 @Se estiver ocupado vai para a proxima posicao
		bne loop_busca_callback

		@Se estiver vazio, guarda os valores de id_sonar, distancia minima e endereco da funcao
		str r1, [r6, r5] @ID_SONAR
		add r5, r5, #4
		str r2, [r6, r5]@DISTANCIA
		add r5, r5, #4
		str r3, [r6, r5]@ENDERECO
		ldr r8, [r4]
		add r8, r8, #1
		str r8, [r4]@NUM_CALLBACKS
	sai_da_busca:
		ldmfd sp!, {r1-r11, lr}
		mov r0, #0
		movs pc, lr


	retorna_menos_um:
		ldmfd sp!, {r1-r11, lr}
		mov r0, #-1
		movs pc, lr

	retorna_menos_dois:
		ldmfd sp!, {r1-r11, lr}
		mov r0, #-2
		movs pc, lr
@--------SYSCALL SET_CALLBACK---------------@

@--------SYSCALL DE UM MOTOR---------------@
sys_set_motor_speed:

  stmfd sp!, {r1-r11, lr} @ Salva os registradores na pilha

	msr CPSR_c, #0x1F @ Muda para o modo SYSTEM
	ldmfd sp!, {r4, r5} @ Pega os parametros da pilha do USER/SYSTEM
    sub sp, sp, #8 @ Volta a pilha para o estado antigo
	msr CPSR_c, #0x13 @ Volta para o modo SUPERVISOR

	mov r0, #0
	cmp r4, #0
	beq motor
	cmp r4, #1
	beq motor
	mov r0, #-1
	b		fim
	motor:
		cmp r5, #0
		movlt r0, #-2
		cmp r5, #63
		movgt r0, #-2
		cmp r0, #0
		bne fim
		cmp r4, #0
		moveq r5, r5, lsl #19
		ldreq r6, =0xFE03FFFF
		cmp r4, #1
		moveq r5, r5, lsl #26
		ldreq r6, =0x1FFFFFF
		ldr r8, =GPIO_BASE
		ldr r9, [r8]
		and r9, r9, r6
		orr r5, r9, r5
		str r5, [r8]

        ldmfd sp!, {r1-r11, lr}
		movs pc, lr
@--------SYSCALL DE UM MOTOR---------------@

@--------SYSCALL DE MOTORES----------------@
sys_set_motors_speed:

    stmfd sp!, {r1-r11, lr} @ Salva os registradores na pilha

	msr CPSR_c, #0x1F @ Muda para o modo SYSTEM
	ldmfd sp!, {r4, r5} @ Pega os parametros da pilha do USER/SYSTEM
    sub sp, sp, #8 @ Volta a pilha para o estado antigo
	msr CPSR_c, #0x13 @ Volta para o modo SUPERVISOR

	mov r0, #0
	cmp r4, #0
	movlt r0, #-1
	cmp r4, #63
	movgt r0, #-1
	cmp r0, #0
	bne fim
	cmp r5, #0
	movlt r0, #-2
	cmp r5, #63
	movgt r0, #-2
	cmp r0, #0
	bne fim
	mov r4, r4, lsl #19
	mov r5, r5, lsl #26
	add r5, r5, r4
	ldr r6, =0x3FFFF
	ldr r8, =GPIO_BASE
	ldr r9, [r8]
	and r9, r9, r6
	orr r5, r5, r9
	str r5, [r8]
    ldmfd sp!, {r1-r11, lr}
	movs pc, lr
@--------SYSCALL DE MOTORES----------------@

@--------SYSCALL DE GET_TIME---------------@
sys_get_time:
	stmfd sp!, {r1-r11, lr}
	ldr r4, =system_time
	ldr r0, [r4]
	ldmfd sp!, {r1-r11, lr}
	movs pc, lr
@--------SYSCALL DE GET_TIME---------------@

@--------SYSCALL DE SET_TIME---------------@
sys_set_time:

  stmfd sp!, {r1-r11, lr} @ Salva os registradores na pilha

	msr CPSR_c, #0x1F @ Muda para o modo SYSTEM
	ldmfd sp!, {r4} @ Pega os parametros da pilha do USER/SYSTEM
    sub sp, sp, #4 @ Volta a pilha para o estado antigo
	msr CPSR_c, #0x13 @ Volta para o modo SUPERVISOR

	ldr r5, =system_time
	str r4, [r5]

    ldmfd sp!, {r1-r11, lr}
	movs pc, lr
@--------SYSCALL DE SET_TIME---------------@

@--------SYSCALL DE SET_ALARM--------------@
sys_set_alarm:

  stmfd sp!, {r1-r11, lr} @ Salva os registradores na pilha

	msr CPSR_c, #0x1F @ Muda para o modo SYSTEM
	ldmfd sp!, {r4, r5} @ Pega os parametros da pilha do USER/SYSTEM
	sub sp, sp, #8 @ Volta a pilha para o estado antigo
	msr CPSR_c, #0x13 @ Volta para o modo SUPERVISOR

	mov r0, #0
	ldr r6, =num_alarms
	ldr r8, [r6]
	cmp r8, #8
	moveq r0, #-1
	ldr r6, =system_time
	ldr r6, [r6]
	cmp r5, r6
	movlt r0, #-2
	cmp r0, #0
	bne fim
	mov r9, pc
	b busca_alarme_inativo
	ldmfd sp!, {r6}
	str r4, [r6]
	str r5, [r6, #4]
	ldr r6, =num_alarms
	ldr r8, [r6]
	add r8, r8, #1
	str r8, [r6]

  ldmfd sp!, {r1-r11, lr}
	movs pc, lr
@--------SYSCALL DE SET_ALARM--------------@

@--------SYSCALL MODO USER-----------------@
modo_user:
	msr CPSR_c, #0xD2
	b loopizinho
@--------SYSCALL MODO USER-----------------@

@--------SYSCALL CALLBACK CHANGE MODE------@
change_mode_proximity_callback:
    msr CPSR_c, #0xD2
    b volta_da_syscall_proximity_callback
@--------SYSCALL CALLBACK CHANGE MODE------@
busca_alarme_inativo:
	ldr r8, =num_alarms
	ldr r8, [r8]
	ldr r1, =alarm_vector
	cmp r8, #0
	beq sai
	loop_alarme_inativo:
		ldr r2, [r1]
		cmp r2, #0
		addne r1, r1, #8
		bne loop_alarme_inativo
	sai:
	stmfd sp!, {r1}
	mov pc, r9
delay:
		stmfd sp!, {r4}
		mov r4, #0
		loop_delay:
			add r4, r4, #1
			cmp r4, #50
			bne loop_delay
		ldmfd sp!, {r4}

		mov pc, r9
fim:
	ldmfd sp!, {r1-r11, lr}
	movs pc, lr

.data
system_time:
.word 0
num_alarms:
.word 0
alarm_vector:
.fill 16, 4, 0
.align 4
ta_rolando_um_callback:
.word 0
NUM_CALLBACKS:
.word 0
vetor_proximity_callback:
.fill 24, 4, 16
.align 4
