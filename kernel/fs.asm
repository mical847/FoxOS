fs_mount:
    mov byte [fs_ready], 0
    mov eax, FS_HEADER_SECTOR
    mov rdi, fs_header_buffer
    call ata_read_sector
    jc .failed
    mov rax, 0x314B534944584F46
    cmp qword [fs_header_buffer], rax
    jne .failed
    cmp dword [fs_header_buffer + 8], 1
    jne .failed
    cmp dword [fs_header_buffer + 12], FS_ENTRY_COUNT
    jne .failed
    cmp dword [fs_header_buffer + 16], FS_DATA_START
    jne .failed
    cmp dword [fs_header_buffer + 20], FS_DATA_SECTORS
    jne .failed
    xor r12d, r12d
.read_table:
    mov eax, FS_HEADER_SECTOR + 1
    add eax, r12d
    mov rdi, r12
    shl rdi, 9
    add rdi, fs_table
    call ata_read_sector
    jc .failed
    inc r12d
    cmp r12d, 8
    jb .read_table
    mov eax, FS_HEADER_SECTOR + 9
    mov rdi, fs_bitmap
    call ata_read_sector
    jc .failed
    mov byte [fs_ready], 1
    clc
    ret
.failed:
    stc
    ret

ata_read_sector:
    push rbx
    push rcx
    push rdx
    push rsi
    push r8
    push r9
    mov ebx, eax
    mov r8, rdi
    mov dx, 0x1F6
    mov eax, ebx
    shr eax, 24
    and al, 0x0F
    or al, 0xE0
    out dx, al
    mov dx, 0x1F2
    mov al, 1
    out dx, al
    mov eax, ebx
    mov dx, 0x1F3
    out dx, al
    shr eax, 8
    mov dx, 0x1F4
    out dx, al
    shr eax, 8
    mov dx, 0x1F5
    out dx, al
    mov dx, 0x1F7
    mov al, 0x20
    out dx, al
    call ata_wait_drq
    jc .done
    mov dx, 0x1F0
    mov rdi, r8
    mov ecx, 256
    cld
    rep insw
    clc
.done:
    pop r9
    pop r8
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

ata_write_sector:
    push rbx
    push rcx
    push rdx
    push rsi
    push r8
    push r9
    mov ebx, eax
    mov r8, rdi
    mov dx, 0x1F6
    mov eax, ebx
    shr eax, 24
    and al, 0x0F
    or al, 0xE0
    out dx, al
    mov dx, 0x1F2
    mov al, 1
    out dx, al
    mov eax, ebx
    mov dx, 0x1F3
    out dx, al
    shr eax, 8
    mov dx, 0x1F4
    out dx, al
    shr eax, 8
    mov dx, 0x1F5
    out dx, al
    mov dx, 0x1F7
    mov al, 0x30
    out dx, al
    call ata_wait_drq
    jc .done
    mov dx, 0x1F0
    mov rsi, r8
    mov ecx, 256
    cld
    rep outsw
    call ata_wait_idle
.done:
    pop r9
    pop r8
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

ata_wait_drq:
    mov ecx, 0x100000
.poll:
    mov dx, 0x1F7
    in al, dx
    test al, 0x80
    jnz .retry
    test al, 0x21
    jnz .error
    test al, 0x08
    jnz .ready
.retry:
    loop .poll
.error:
    stc
    ret
.ready:
    clc
    ret

ata_wait_idle:
    mov ecx, 0x100000
.poll:
    mov dx, 0x1F7
    in al, dx
    test al, 0x80
    jnz .retry
    test al, 0x21
    jnz .error
    clc
    ret
.retry:
    loop .poll
.error:
    stc
    ret

fs_resolve:
    push rbx
    push rcx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    mov [fs_path_cursor], rdi
    mov qword [fs_parent_id], 0
    mov byte [fs_missing_final], 0
.component:
    mov rsi, [fs_path_cursor]
.skip_slashes:
    cmp rsi, 0x420000
    jae .invalid
    cmp byte [rsi], '/'
    jne .component_start
    inc rsi
    jmp .skip_slashes
.component_start:
    mov [fs_path_cursor], rsi
    cmp byte [rsi], 0
    je .root
    mov qword [fs_name_buffer], 0
    mov qword [fs_name_buffer + 8], 0
    mov qword [fs_name_buffer + 16], 0
    xor ecx, ecx
.copy_name:
    cmp rsi, 0x420000
    jae .invalid
    mov al, [rsi]
    test al, al
    jz .name_ready
    cmp al, '/'
    je .name_ready
    cmp ecx, 19
    jae .invalid
    mov [fs_name_buffer + rcx], al
    inc ecx
    inc rsi
    jmp .copy_name
.name_ready:
    mov [fs_path_cursor], rsi
    mov byte [fs_name_buffer + rcx], 0
    mov r10, rsi
.check_final:
    cmp r10, 0x420000
    jae .invalid
    cmp byte [r10], '/'
    jne .final_checked
    inc r10
    jmp .check_final
.final_checked:
    xor r11d, r11d
    cmp byte [r10], 0
    setz r11b
    mov [fs_path_final], r11b
    xor ebx, ebx
.search_entry:
    cmp ebx, FS_ENTRY_COUNT
    jae .missing
    mov rax, rbx
    shl rax, 5
    lea r9, [fs_table + rax]
    cmp byte [r9 + 20], 0
    je .next_entry
    movzx eax, word [r9 + 29]
    cmp rax, [fs_parent_id]
    jne .next_entry
    lea rdi, [r9]
    mov rsi, fs_name_buffer
    mov ecx, 20
    repe cmpsb
    je .entry_found
.next_entry:
    inc ebx
    jmp .search_entry
.entry_found:
    cmp byte [fs_path_final], 1
    je .found
    cmp byte [r9 + 20], 1
    jne .invalid
    mov eax, ebx
    inc eax
    mov [fs_parent_id], rax
    jmp .component
.found:
    mov rax, r9
    mov edx, ebx
    inc edx
    clc
    jmp .return
.missing:
    cmp byte [fs_path_final], 1
    jne .invalid
    mov byte [fs_missing_final], 1
    stc
    jmp .return
.root:
    xor eax, eax
    xor edx, edx
    clc
    jmp .return
.invalid:
    mov byte [fs_missing_final], 0
    stc
.return:
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    ret

fs_entry_id:
    mov rax, rdi
    sub rax, fs_table
    shr rax, 5
    inc rax
    ret

fs_entry_from_id:
    test rdi, rdi
    jz .invalid
    cmp rdi, FS_ENTRY_COUNT
    ja .invalid
    dec rdi
    shl rdi, 5
    lea rax, [fs_table + rdi]
    cmp byte [rax + 20], 0
    je .invalid
    ret
.invalid:
    xor eax, eax
    ret

fs_create_entry:
    mov [fs_selected_type], al
    cmp byte [fs_ready], 1
    jne .error
    cmp byte [fs_missing_final], 1
    jne .error
    xor ebx, ebx
.find_slot:
    cmp ebx, FS_ENTRY_COUNT
    jae .error
    mov rax, rbx
    shl rax, 5
    lea rdi, [fs_table + rax]
    cmp byte [rdi + 20], 0
    je .slot_found
    inc ebx
    jmp .find_slot
.slot_found:
    mov [fs_selected_index], ebx
    mov [fs_entry_pointer], rdi
    xor eax, eax
    mov ecx, FS_ENTRY_SIZE / 8
    rep stosq
    mov rdi, [fs_entry_pointer]
    mov rsi, fs_name_buffer
    mov ecx, 20
    rep movsb
    mov rdi, [fs_entry_pointer]
    mov al, [fs_selected_type]
    mov [rdi + 20], al
    mov ax, [fs_parent_id]
    mov [rdi + 29], ax
    call fs_sync_metadata
    jc .error
    mov rax, [fs_entry_pointer]
    mov edx, [fs_selected_index]
    inc edx
    clc
    ret
.error:
    stc
    ret

fs_sync_metadata:
    xor r12d, r12d
.write_table:
    mov eax, FS_HEADER_SECTOR + 1
    add eax, r12d
    mov rdi, r12
    shl rdi, 9
    add rdi, fs_table
    call ata_write_sector
    jc .error
    inc r12d
    cmp r12d, 8
    jb .write_table
    mov eax, FS_HEADER_SECTOR + 9
    mov rdi, fs_bitmap
    call ata_write_sector
    ret
.error:
    stc
    ret

fs_allocate_extent:
    test ecx, ecx
    jz .no_space
    cmp ecx, FS_DATA_SECTORS
    ja .no_space
    mov [fs_need_sectors], ecx
    xor r8d, r8d
.candidate:
    mov eax, r8d
    add eax, [fs_need_sectors]
    cmp eax, FS_DATA_SECTORS
    ja .no_space
    xor r9d, r9d
.check_candidate:
    cmp r9d, [fs_need_sectors]
    jae .allocate
    mov ebx, r8d
    add ebx, r9d
    mov eax, ebx
    shr eax, 3
    movzx eax, byte [fs_bitmap + rax]
    mov ecx, ebx
    and ecx, 7
    bt eax, ecx
    jc .next_candidate
    inc r9d
    jmp .check_candidate
.next_candidate:
    inc r8d
    jmp .candidate
.allocate:
    mov [fs_alloc_start], r8d
    mov ecx, [fs_need_sectors]
    mov [fs_alloc_count], ecx
    call fs_mark_extent
    mov eax, [fs_alloc_start]
    clc
    ret
.no_space:
    stc
    ret

fs_release_extent:
    mov [fs_alloc_start], eax
    mov [fs_alloc_count], ecx
    mov r8d, eax
    mov r9d, ecx
.release_next:
    test r9d, r9d
    jz .done
    mov eax, r8d
    mov ecx, eax
    and ecx, 7
    shr eax, 3
    mov dl, 1
    shl dl, cl
    not dl
    and [fs_bitmap + rax], dl
    inc r8d
    dec r9d
    jmp .release_next
.done:
    ret

fs_mark_extent:
    mov r8d, [fs_alloc_start]
    mov r9d, [fs_alloc_count]
.mark_next:
    test r9d, r9d
    jz .done
    mov eax, r8d
    mov ecx, eax
    and ecx, 7
    shr eax, 3
    mov dl, 1
    shl dl, cl
    or [fs_bitmap + rax], dl
    inc r8d
    dec r9d
    jmp .mark_next
.done:
    ret

fs_truncate_file:
    mov [fs_entry_pointer], rdi
    movzx eax, word [rdi + 21]
    movzx ecx, word [rdi + 23]
    call fs_release_extent
    mov rdi, [fs_entry_pointer]
    mov word [rdi + 21], 0
    mov word [rdi + 23], 0
    mov dword [rdi + 25], 0
    jmp fs_sync_metadata

fs_stage_file:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13d, [rdi + 25]
    cmp r13d, FS_DATA_SECTORS * 512
    ja .invalid
    movzx r14d, word [rdi + 23]
    mov eax, r14d
    shl eax, 9
    cmp r13d, eax
    ja .invalid
    movzx r15d, word [rdi + 21]
    mov eax, r15d
    add eax, r14d
    jc .invalid
    cmp eax, FS_DATA_SECTORS
    ja .invalid
    xor ebx, ebx
.next_sector:
    cmp ebx, r13d
    jae .done
    mov eax, ebx
    shr eax, 9
    cmp eax, r14d
    jae .invalid
    add eax, r15d
    jc .invalid
    add eax, FS_DATA_START
    mov rdi, fs_sector_buffer
    call ata_read_sector
    jc .invalid
    mov ecx, r13d
    sub ecx, ebx
    cmp ecx, 512
    jbe .copy_sector
    mov ecx, 512
.copy_sector:
    mov r9d, ecx
    lea rsi, [fs_sector_buffer]
    mov edi, 0x30000
    add rdi, rbx
    cld
    rep movsb
    add ebx, r9d
    cmp ebx, r13d
    jb .next_sector
.done:
    mov eax, 0x30000
    mov edx, r13d
    clc
    jmp .return
.invalid:
    stc
.return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

fs_ensure_capacity:
    mov [fs_io_entry], rdi
    mov [fs_need_sectors], ecx
    movzx eax, word [rdi + 23]
    cmp eax, ecx
    jae .ready
    mov [fs_old_count], eax
    movzx eax, word [rdi + 21]
    mov [fs_old_start], eax
    mov ecx, [fs_need_sectors]
    call fs_allocate_extent
    jc .error
    mov [fs_new_start], eax
    xor r12d, r12d
.copy_old:
    cmp r12d, [fs_old_count]
    jae .update_entry
    mov eax, [fs_old_start]
    add eax, r12d
    add eax, FS_DATA_START
    mov rdi, fs_sector_buffer
    call ata_read_sector
    jc .rollback
    mov eax, [fs_new_start]
    add eax, r12d
    add eax, FS_DATA_START
    mov rdi, fs_sector_buffer
    call ata_write_sector
    jc .rollback
    inc r12d
    jmp .copy_old
.update_entry:
    mov eax, [fs_old_start]
    mov ecx, [fs_old_count]
    call fs_release_extent
    mov rdi, [fs_io_entry]
    mov ax, [fs_new_start]
    mov [rdi + 21], ax
    mov ax, [fs_need_sectors]
    mov [rdi + 23], ax
    call fs_sync_metadata
    ret
.rollback:
    mov eax, [fs_new_start]
    mov ecx, [fs_need_sectors]
    call fs_release_extent
.error:
    stc
    ret
.ready:
    clc
    ret

fs_read_file:
    mov [fs_io_entry], rdi
    mov [fs_io_fd], rsi
    mov [fs_io_user], rdx
    mov [fs_io_remaining], rcx
    mov qword [fs_io_total], 0
    mov rax, [rsi + 24]
    mov [fs_io_position], rax
    mov eax, [rdi + 25]
    mov [fs_io_size], rax
    cmp rax, [fs_io_position]
    jbe .empty
    sub rax, [fs_io_position]
    cmp rax, [fs_io_remaining]
    jbe .available
    mov rax, [fs_io_remaining]
.available:
    mov [fs_io_remaining], rax
.next:
    cmp qword [fs_io_remaining], 0
    je .done
    mov rax, [fs_io_position]
    mov edx, eax
    and edx, 511
    mov [fs_io_sector_offset], edx
    shr rax, 9
    mov [fs_io_sector_index], eax
    mov rdi, [fs_io_entry]
    movzx eax, word [rdi + 21]
    add eax, [fs_io_sector_index]
    add eax, FS_DATA_START
    mov rdi, fs_sector_buffer
    call ata_read_sector
    jc .io_error
    mov eax, 512
    sub eax, [fs_io_sector_offset]
    cmp rax, [fs_io_remaining]
    jbe .part_ready
    mov rax, [fs_io_remaining]
.part_ready:
    mov [fs_io_part], rax
    mov rsi, fs_sector_buffer
    add rsi, [fs_io_sector_offset]
    mov rdi, [fs_io_user]
    mov rcx, [fs_io_part]
    cld
    rep movsb
    mov rax, [fs_io_part]
    add [fs_io_user], rax
    add [fs_io_position], rax
    add [fs_io_total], rax
    sub [fs_io_remaining], rax
    jmp .next
.done:
    mov rdi, [fs_io_fd]
    mov rax, [fs_io_position]
    mov [rdi + 24], rax
    mov rax, [fs_io_total]
    ret
.empty:
    xor eax, eax
    ret
.io_error:
    cmp qword [fs_io_total], 0
    jne .done
    mov rax, -5
    ret

fs_write_file:
    mov [fs_io_user], rdi
    mov [fs_io_fd], rsi
    mov [fs_io_entry], rdx
    mov [fs_io_remaining], rcx
    mov qword [fs_io_total], 0
    mov rax, [rsi + 24]
    mov [fs_io_position], rax
    mov eax, [rdx + 25]
    mov [fs_io_size], rax
    test rcx, rcx
    jz .empty
    mov rax, [fs_io_position]
    add rax, rcx
    jc .too_large
    cmp rax, FS_DATA_SECTORS * 512
    ja .too_large
    add rax, 511
    shr rax, 9
    mov ecx, eax
    mov rdi, [fs_io_entry]
    call fs_ensure_capacity
    jc .io_error
.next:
    cmp qword [fs_io_remaining], 0
    je .finish
    mov rax, [fs_io_position]
    mov edx, eax
    and edx, 511
    mov [fs_io_sector_offset], edx
    shr rax, 9
    mov [fs_io_sector_index], eax
    mov eax, 512
    sub eax, [fs_io_sector_offset]
    cmp rax, [fs_io_remaining]
    jbe .part_ready
    mov rax, [fs_io_remaining]
.part_ready:
    mov [fs_io_part], rax
    cmp dword [fs_io_sector_offset], 0
    jne .read_modify_sector
    cmp qword [fs_io_part], 512
    je .write_sector
.read_modify_sector:
    mov rdi, [fs_io_entry]
    movzx eax, word [rdi + 23]
    cmp eax, [fs_io_sector_index]
    jbe .zero_sector
    movzx eax, word [rdi + 21]
    add eax, [fs_io_sector_index]
    add eax, FS_DATA_START
    mov rdi, fs_sector_buffer
    call ata_read_sector
    jc .io_error
    jmp .copy_to_sector
.zero_sector:
    mov rdi, fs_sector_buffer
    xor eax, eax
    mov ecx, 512 / 8
    rep stosq
.copy_to_sector:
    mov rdi, fs_sector_buffer
    add rdi, [fs_io_sector_offset]
    mov rsi, [fs_io_user]
    mov rcx, [fs_io_part]
    cld
    rep movsb
.write_sector:
    mov rdi, [fs_io_entry]
    movzx eax, word [rdi + 21]
    add eax, [fs_io_sector_index]
    add eax, FS_DATA_START
    mov rdi, fs_sector_buffer
    call ata_write_sector
    jc .io_error
    mov rax, [fs_io_part]
    add [fs_io_user], rax
    add [fs_io_position], rax
    add [fs_io_total], rax
    sub [fs_io_remaining], rax
    jmp .next
.finish:
    mov rdi, [fs_io_entry]
    mov rax, [fs_io_position]
    cmp rax, [fs_io_size]
    jbe .store_position
    mov [fs_io_size], rax
    mov [rdi + 25], eax
    call fs_sync_metadata
    jc .write_failed
.store_position:
    mov rdi, [fs_io_fd]
    mov rax, [fs_io_position]
    mov [rdi + 24], rax
    mov rax, [fs_io_total]
    ret
.empty:
    xor eax, eax
    ret
.too_large:
    mov rax, -27
    ret
.io_error:
    cmp qword [fs_io_total], 0
    jne .write_failed
    mov rax, -5
    ret
.write_failed:
    mov rdi, [fs_io_entry]
    mov rax, [fs_io_position]
    cmp rax, [fs_io_size]
    jbe .failed_position
    mov [fs_io_size], rax
    mov [rdi + 25], eax
    call fs_sync_metadata
.failed_position:
    mov rdi, [fs_io_fd]
    mov rax, [fs_io_position]
    mov [rdi + 24], rax
    cmp qword [fs_io_total], 0
    je .failed_without_progress
    mov rax, [fs_io_total]
    ret
.failed_without_progress:
    mov rax, -5
    ret
