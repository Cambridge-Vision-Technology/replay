export const fetchImpl = (url, method, body) => {
  return fetch(url, {
    method: method,
    body: body,
    headers: {
      "Content-Type": "application/json",
    },
  }).then(async (response) => {
    const responseBody = await response.text();
    return {
      statusCode: response.status,
      body: responseBody,
    };
  });
};
