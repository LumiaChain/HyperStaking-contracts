import Link from "next/link";
import React, { FC } from "react";

interface SunnyButtonProps {
  href?: string;
  title?: string;
  className?: string;
  children: React.ReactNode;
}

const SunnyButton: FC<SunnyButtonProps> = ({
  href = "#",
  title = "Button",
  className = "min-w-36 px-2 py-2",
  children,
}) => {
  return (
    <div className="relative inline-flex group">
      <div className="
        absolute transition-all duration-1000 opacity-0
        bg-gradient-to-r from-sky-200 via-sky-300 to-sky-200
        group-hover:opacity-0 group-hover:-inset-1 group-hover:duration-200
        animate-tilt rounded-xl blur-[12px] -inset-px
        ">
      </div>
      <Link href={href} legacyBehavior>
        <a title={title}
          className={`
            relative inline-flex items-center justify-center
            text-base font-bold text-white transition-all
            duration-200 font-pj rounded-xl
            ${className}
          `}
          role="button">
          {children}
        </a>
      </Link>
    </div>
  );
};

export default SunnyButton;
