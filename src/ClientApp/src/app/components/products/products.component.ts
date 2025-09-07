import { Component, inject } from '@angular/core';
import { ReactiveFormsModule, FormBuilder, Validators } from '@angular/forms';
import { MatCardModule } from '@angular/material/card';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatButtonModule } from '@angular/material/button';
import { MatTableModule } from '@angular/material/table';
import { NgIf, DecimalPipe } from '@angular/common';
import { ProductService } from '../../services/product.service';
import { Product, CreateProductRequest } from '../../models/product.model';

@Component({
  selector: 'app-products',
  standalone: true,
  imports: [
    ReactiveFormsModule,
    MatCardModule,
    MatFormFieldModule,
    MatInputModule,
    MatButtonModule,
    MatTableModule,
    NgIf,
    DecimalPipe
  ],
  templateUrl: './products.component.html',
  styleUrl: './products.component.scss'
})
export class ProductsComponent {
  private fb = inject(FormBuilder);
  private productService = inject(ProductService);

  products: Product[] = [];
  loading = false;
  displayedColumns: string[] = ['name', 'price', 'stockQuantity', 'actions'];

  form = this.fb.group({
    name: ['', [Validators.required, Validators.maxLength(150)]],
    description: [''],
    price: [0, [Validators.required, Validators.min(0)]],
    stockQuantity: [0, [Validators.required, Validators.min(0)]]
  });

  ngOnInit() { this.load(); }

  load() {
    this.loading = true;
    this.productService.getProducts().subscribe({
      next: (data: Product[]) => { this.products = data; this.loading = false; },
      error: () => { this.loading = false; }
    });
  }

  submit() {
    if (this.form.invalid) { this.form.markAllAsTouched(); return; }
    const payload = this.form.value as CreateProductRequest;
    this.productService.createProduct(payload).subscribe({
      next: (created: Product) => {
        this.products = [created, ...this.products];
        this.form.reset();
      }
    });
  }

  delete(id: number) {
    this.productService.deleteProduct(id).subscribe({
      next: () => this.products = this.products.filter(p => p.id !== id)
    });
  }
}
