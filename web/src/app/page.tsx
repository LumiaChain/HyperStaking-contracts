"use client";

import Image from "next/image";

import RainbowButton from "../components/RainbowButton";
import { useAccount } from "wagmi";

import Staking from "../components/Staking";

export default function Home() {
  const { isConnected } = useAccount();

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
      <footer className="row-start-3 flex gap-6 flex-wrap items-center justify-center">
        <a
          className="flex items-center gap-2 hover:underline hover:underline-offset-4"
          href="https://nextjs.org/learn?utm_source=create-next-app&utm_medium=appdir-template-tw&utm_campaign=create-next-app"
          target="_blank"
          rel="noopener noreferrer"
        >
          <Image
            aria-hidden
            src="https://nextjs.org/icons/file.svg"
            alt="File icon"
            width={16}
            height={16}
          />
          Learn
        </a>
        <a
          className="flex items-center gap-2 hover:underline hover:underline-offset-4"
          href="https://vercel.com/templates?framework=next.js&utm_source=create-next-app&utm_medium=appdir-template-tw&utm_campaign=create-next-app"
          target="_blank"
          rel="noopener noreferrer"
        >
          <Image
            aria-hidden
            src="https://nextjs.org/icons/window.svg"
            alt="Window icon"
            width={16}
            height={16}
          />
          Examples
        </a>
        <a
          className="flex items-center gap-2 hover:underline hover:underline-offset-4"
          href="https://nextjs.org?utm_source=create-next-app&utm_medium=appdir-template-tw&utm_campaign=create-next-app"
          target="_blank"
          rel="noopener noreferrer"
        >
          <Image
            aria-hidden
            src="https://nextjs.org/icons/globe.svg"
            alt="Globe icon"
            width={16}
            height={16}
          />
          Go to nextjs.org →
        </a>
      </footer>
    </div>
  );
}
