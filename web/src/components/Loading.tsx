import React, { useState, useCallback, useImperativeHandle, forwardRef } from "react";

const Loading = forwardRef((_, ref) => {
  const [loadingMessages, setLoadingMessages] = useState<Map<number, string>>(new Map());
  const [idCounter, setIdCounter] = useState(0); // Initialize counter

  // Add a loading message and return the generated ID
  const addLoadingMsg = useCallback((message: string) => {
    const id = idCounter; // Use the current value of the counter
    setIdCounter((prev) => prev + 1); // Increment the counter

    setLoadingMessages((prevMessages) => {
      if (prevMessages.has(id)) {
        console.warn(`Message with id "${id}" already exists.`);
        return prevMessages;
      }
      const updatedMessages = new Map(prevMessages);
      updatedMessages.set(id, message); // Store the message with the generated ID
      return updatedMessages;
    });

    return id; // Return the generated ID
  }, [idCounter]);

  // Remove a loading message
  const removeLoadingMsg = useCallback((id: number) => {
    setLoadingMessages((prevMessages) => {
      if (!prevMessages.has(id)) {
        console.warn(`Message with id "${id}" does not exist.`);
        return prevMessages;
      }
      const updatedMessages = new Map(prevMessages);
      updatedMessages.delete(id);
      return updatedMessages;
    });
  }, []);

  // Get the first active loading message or "Sync: OK"
  const getFirstLoadingMessage = () => {
    if (loadingMessages.size === 0) {
      return "Sync: OK";
    }
    // Get the first entry in the map
    const firstMessage = loadingMessages.values().next().value;
    return firstMessage;
  };

  // Expose addLoadingMsg and removeLoadingMsg via ref
  useImperativeHandle(ref, () => ({
    addLoadingMsg,
    removeLoadingMsg,
  }));

  return (
    <div className="flex flex-col text-md font-semibold items-center justify-start h-16">
      <p>{getFirstLoadingMessage()}</p>
    </div>
  );
});

// Set displayName for easier debugging
Loading.displayName = "LoadingComponent";

export default Loading;
