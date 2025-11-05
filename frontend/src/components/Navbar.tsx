import { FC } from 'react';

interface NavbarProps {
  userType: 'user' | 'employee' | 'admin';
  address: string;
}

export const Navbar: FC<NavbarProps> = ({ userType, address }) => {
  return (
    <nav className="bg-gray-800 text-white">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-16">
          <div className="flex items-center">
            <div className="flex-shrink-0">
              <span className="text-xl font-bold">POP Protocol</span>
            </div>
            <div className="hidden md:block">
              <div className="ml-10 flex items-baseline space-x-4">
                {userType === 'user' && (
                  <>
                    <a href="/user/tasks" className="hover:bg-gray-700 px-3 py-2 rounded-md">My Tasks</a>
                    <a href="/user/reputation" className="hover:bg-gray-700 px-3 py-2 rounded-md">My Reputation</a>
                  </>
                )}
                {userType === 'employee' && (
                  <>
                    <a href="/employee/assignments" className="hover:bg-gray-700 px-3 py-2 rounded-md">Assignments</a>
                    <a href="/employee/manage" className="hover:bg-gray-700 px-3 py-2 rounded-md">Manage Users</a>
                  </>
                )}
                {userType === 'admin' && (
                  <>
                    <a href="/admin/employees" className="hover:bg-gray-700 px-3 py-2 rounded-md">Manage Employees</a>
                    <a href="/admin/system" className="hover:bg-gray-700 px-3 py-2 rounded-md">System Settings</a>
                  </>
                )}
              </div>
            </div>
          </div>
          <div className="flex items-center">
            <div className="bg-gray-900 px-4 py-2 rounded-lg text-sm">
              {address.slice(0, 6)}...{address.slice(-4)}
            </div>
          </div>
        </div>
      </div>
    </nav>
  );
};