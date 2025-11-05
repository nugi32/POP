"use client";

import { Button } from '@/components/Button';
import Link from 'next/link';

export default function Home() {
  return (
    <div className="min-h-screen bg-gray-50">
      <div className="bg-white shadow">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-6">
            <div className="text-2xl font-bold text-gray-900">POP Protocol</div>
            <div className="space-x-4">
              <Link href="/user/dashboard">
                <Button variant="secondary">User Dashboard</Button>
              </Link>
              <Link href="/employee/dashboard">
                <Button variant="secondary">Employee Dashboard</Button>
              </Link>
              <Link href="/admin/dashboard">
                <Button variant="secondary">Admin Dashboard</Button>
              </Link>
            </div>
          </div>
        </div>
      </div>

      <main>
        <div className="max-w-7xl mx-auto py-16 px-4 sm:py-24 sm:px-6 lg:px-8">
          <div className="text-center">
            <h1 className="text-4xl font-extrabold text-gray-900 sm:text-5xl md:text-6xl">
              Welcome to POP Protocol
            </h1>
            <p className="mt-3 max-w-md mx-auto text-base text-gray-500 sm:text-lg md:mt-5 md:text-xl md:max-w-3xl">
              A decentralized platform for task management, reputation tracking, and employee assignment.
            </p>
            <div className="mt-10 flex justify-center gap-8">
              <Link href="/user/dashboard">
                <Button size="lg">Get Started as User</Button>
              </Link>
              <Link href="/employee/dashboard">
                <Button size="lg" variant="secondary">Employee Login</Button>
              </Link>
            </div>
          </div>

          <div className="mt-32 grid grid-cols-1 gap-8 md:grid-cols-3">
            <div className="text-center">
              <div className="rounded-lg bg-white shadow-lg p-6">
                <h3 className="text-lg font-semibold text-gray-900">For Users</h3>
                <p className="mt-2 text-gray-600">
                  Create tasks, build reputation, and engage with the community.
                </p>
              </div>
            </div>
            <div className="text-center">
              <div className="rounded-lg bg-white shadow-lg p-6">
                <h3 className="text-lg font-semibold text-gray-900">For Employees</h3>
                <p className="mt-2 text-gray-600">
                  Manage tasks, assign work, and oversee user activities.
                </p>
              </div>
            </div>
            <div className="text-center">
              <div className="rounded-lg bg-white shadow-lg p-6">
                <h3 className="text-lg font-semibold text-gray-900">For Admins</h3>
                <p className="mt-2 text-gray-600">
                  Control system parameters and manage employee assignments.
                </p>
              </div>
            </div>
          </div>
        </div>
      </main>
    </div>
  );
}