"use client";

import { useState, useEffect } from "react";
import { useAccount } from "wagmi";

import AuthModal from "@/components/AuthModal";
import RainbowButton from "@/components/RainbowButton";
import Staking from "@/components/Staking";
import Footer from "@/components/Footer";

export default function Home() {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [isLoading, setIsLoading] = useState(true);

  const { isConnected } = useAccount();

  // Check localStorage to see if the user is already authenticated
  useEffect(() => {
    const storedAuthStatus = localStorage.getItem("isAuthenticated");
    if (storedAuthStatus === "true") {
      setIsAuthenticated(true); // User is already authenticated
    }

    setIsLoading(false);
  }, []);

  // Callback function to update authentication status
  const handleAuthenticate = (status: boolean) => {
    setIsAuthenticated(status);
    if (status) {
      // Store the authentication status in localStorage
      localStorage.setItem("isAuthenticated", "true");
    } else {
      localStorage.removeItem("isAuthenticated"); // Clear if unauthenticated
    }
  };

  // console.log("isLoading", isLoading);
  // console.log("isAuth", isAuthenticated);
  // console.log("isConnected", isConnected);

  if (isLoading) {
    return null; // Don't render anything while loading
  }

  if (!isAuthenticated) {
    return <AuthModal onAuthenticate={handleAuthenticate} />;
  }

  return (
    <div className="grid grid-rows-[10px_1fr_20px] items-center justify-items-center min-h-screen px-5 p-8 pb-20 gap-16 font-[family-name:var(--font-geist-sans)]">
      <header className="relative min-w-full">
        <div className="container mx-auto h-[100px] flex items-center justify-between p-10">

          <h1 className="text-lg font-bold text-2xl">Lumia HyperStaking [TestWeb]</h1>
          <nav className="flex basis-1/5 items-center justify-between">
            <a href="#" className="px-3">Home</a>
            <a href="#" className="px-3">Docs</a>

            <RainbowButton />

          </nav>
        </div>
        <div className="absolute bottom-0 left-0 w-full h-4 bg-gradient-to-b from-slate-900 from-10% to-60% to-transparent border-t border-slate-800"></div>
      </header>

      <main className="flex flex-col gap-8 row-start-2 items-center sm:items-start">

        {
          isConnected ? <Staking /> : <div className="text-2xl">Connect Wallet First</div>
        }

      </main>
      <Footer />
    </div>
  );
}
