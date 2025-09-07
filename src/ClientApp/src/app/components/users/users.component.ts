import { Component, OnInit, inject } from '@angular/core';
import { FormBuilder, FormGroup, Validators, ReactiveFormsModule } from '@angular/forms';
import { MatSnackBar, MatSnackBarModule } from '@angular/material/snack-bar';
import { MatCardModule } from '@angular/material/card';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatButtonModule } from '@angular/material/button';
import { MatTableModule } from '@angular/material/table';
import { MatIconModule } from '@angular/material/icon';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { NgIf, DatePipe } from '@angular/common';
import { UserService } from '../../services/user.service';
import { User, CreateUserRequest } from '../../models/user.model';

@Component({
  selector: 'app-users',
  standalone: true,
  imports: [
    ReactiveFormsModule,
    MatSnackBarModule,
    MatCardModule,
    MatFormFieldModule,
    MatInputModule,
    MatButtonModule,
    MatTableModule,
    MatIconModule,
    MatProgressSpinnerModule,
    NgIf,
    DatePipe
  ],
  templateUrl: './users.component.html',
  styleUrl: './users.component.scss'
})
export class UsersComponent implements OnInit {
  private userService = inject(UserService);
  private formBuilder = inject(FormBuilder);
  private snackBar = inject(MatSnackBar);

  users: User[] = [];
  userForm: FormGroup = this.formBuilder.group({
    firstName: ['', [Validators.required, Validators.minLength(2)]],
    lastName: ['', [Validators.required, Validators.minLength(2)]],
    email: ['', [Validators.required, Validators.email]]
  });
  displayedColumns: string[] = ['id', 'firstName', 'lastName', 'email', 'createdAt', 'actions'];
  loading = false;
  editingUser: User | null = null;

  ngOnInit(): void {
    this.loadUsers();
  }

  loadUsers(): void {
    this.loading = true;
    this.userService.getUsers().subscribe({
      next: (users) => { this.users = users; this.loading = false; },
      error: (error) => { this.showError('Failed to load users: ' + error); this.loading = false; }
    });
  }

  onSubmit(): void {
    if (!this.userForm.valid) return;
    const userRequest: CreateUserRequest = this.userForm.value as CreateUserRequest;
    if (this.editingUser) {
      this.updateUser(this.editingUser.id, userRequest);
    } else {
      this.createUser(userRequest);
    }
  }

  createUser(userRequest: CreateUserRequest): void {
    this.userService.createUser(userRequest).subscribe({
      next: (user) => {
        this.users.push(user);
        this.userForm.reset();
        this.showSuccess('User created successfully');
      },
      error: (error) => this.showError('Failed to create user: ' + error)
    });
  }

  updateUser(id: number, userRequest: CreateUserRequest): void {
    this.userService.updateUser(id, userRequest).subscribe({
      next: (updatedUser) => {
        const index = this.users.findIndex(u => u.id === id);
        if (index !== -1) this.users[index] = updatedUser;
        this.userForm.reset();
        this.editingUser = null;
        this.showSuccess('User updated successfully');
      },
      error: (error) => this.showError('Failed to update user: ' + error)
    });
  }

  editUser(user: User): void {
    this.editingUser = user;
    this.userForm.patchValue({
      firstName: user.firstName,
      lastName: user.lastName,
      email: user.email
    });
  }

  deleteUser(id: number): void {
    if (!confirm('Are you sure you want to delete this user?')) return;
    this.userService.deleteUser(id).subscribe({
      next: () => {
        this.users = this.users.filter(u => u.id !== id);
        this.showSuccess('User deleted successfully');
      },
      error: (error) => this.showError('Failed to delete user: ' + error)
    });
  }

  cancelEdit(): void {
    this.editingUser = null;
    this.userForm.reset();
  }

  private showSuccess(message: string): void {
    this.snackBar.open(message, 'Close', { duration: 3000 });
  }

  private showError(message: string): void {
    this.snackBar.open(message, 'Close', { duration: 5000 });
  }
}
