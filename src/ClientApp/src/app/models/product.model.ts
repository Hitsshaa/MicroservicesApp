export interface Product {
    id: number;
    name: string;
    description: string;
    price: number;
    stockQuantity: number;
    createdAt: string;
    updatedAt: string;
}

export interface CreateProductRequest {
    name: string;
    description: string;
    price: number;
    stockQuantity: number;
}
