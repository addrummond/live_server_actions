import React from 'react';
import { serverActions } from "live_server_actions";
import { useState, useEffect } from 'react';

const CounterLive = serverActions.CounterWeb.CounterLive;

export const Counter = () => {
  console.log("RENDER COUNTER");
  const [count, setCount] = useState(null);

  // Get the initial count by incrementing by 0
  useEffect(
    () => void CounterLive.update_count(0).then(
      ({new_count}) => { setCount(new_count); }
    ),
    [count]
  );

  return <div>
    <p>Count: {count}</p>
    <button onClick={() => {
      CounterLive.update_count(1).then(
        ({new_count}) => { setCount(new_count); }
      );
    }}>Increment</button>
  </div>;
};
