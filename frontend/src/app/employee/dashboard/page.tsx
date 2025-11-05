"use client";

import { useState } from 'react';
import { Button } from '@/components/Button';
import { Card } from '@/components/Card';
import { Navbar } from '@/components/Navbar';

export default function EmployeeDashboard() {
  const [assignments, setAssignments] = useState([]);
  const [users, setUsers] = useState([]);
  const [employeeAddress, setEmployeeAddress] = useState('');
  const [loading, setLoading] = useState(false);

  const connectWallet = async () => {
    try {
      if (typeof window.ethereum !== 'undefined') {
        const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
        setEmployeeAddress(accounts[0]);
      }
    } catch (error) {
      console.error('Error connecting wallet:', error);
    }
  };

  return (
    <div>
      <Navbar userType="employee" address={employeeAddress || '0x0'} />
      
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {!employeeAddress ? (
          <div className="text-center">
            <Button onClick={connectWallet}>Connect Wallet</Button>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <Card title="Task Assignments">
              {loading ? (
                <div className="text-center py-4">Loading...</div>
              ) : assignments.length === 0 ? (
                <div className="text-center py-4 text-gray-500">No assignments found</div>
              ) : (
                <div>Assignment list will go here</div>
              )}
              <div className="mt-4">
                <Button variant="primary">Create New Assignment</Button>
              </div>
            </Card>

            <Card title="User Management">
              {loading ? (
                <div className="text-center py-4">Loading...</div>
              ) : users.length === 0 ? (
                <div className="text-center py-4 text-gray-500">No users found</div>
              ) : (
                <div>User list will go here</div>
              )}
            </Card>
          </div>
        )}
      </div>
    </div>
  );
}