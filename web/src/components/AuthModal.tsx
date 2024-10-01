import { useState } from "react";

interface AuthModalProps {
  onAuthenticate: (status: boolean) => void; // Define the type of the function prop
}

const AuthModal: React.FC<AuthModalProps> = ({ onAuthenticate }) => {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [errorMessage, setErrorMessage] = useState("");

  // Hardcoded credentials
  const hardcodedUsername = "lumia";
  const hardcodedPassword = "admin";

  // Function to handle form submission
  const handleLogin = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();

    // Check if credentials match
    if (username === hardcodedUsername && password === hardcodedPassword) {
      onAuthenticate(true); // Notify parent component that user is authenticated
      setErrorMessage("");
    } else {
      setErrorMessage("Invalid username or password");
    }
  };

  return (
    <div className="fixed inset-0 flex items-center justify-center bg-gray-900 bg-opacity-75">
      <div className="bg-white text-gray-900 w-96 p-6 rounded-md shadow-md">
        <h2 className="text-lg font-bold mb-4">Login</h2>
        <form onSubmit={handleLogin}>
          <div className="mb-4">
            <label className="block mb-2 font-semibold">Username</label>
            <input
              type="text"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              className="w-full p-2 border border-gray-300 rounded-md"
              required
            />
          </div>
          <div className="mb-4">
            <label className="block mb-2 font-semibold">Password</label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full p-2 border border-gray-300 rounded-md"
              required
            />
          </div>
          {errorMessage && <p className="text-red-500 mb-4">{errorMessage}</p>}
          <button
            type="submit"
            className="bg-blue-500 text-white px-4 py-2 rounded-md hover:bg-blue-600"
          >
            Login
          </button>
        </form>
      </div>
    </div>
  );
};

export default AuthModal;
