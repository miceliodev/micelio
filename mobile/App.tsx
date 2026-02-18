import { StatusBar } from "expo-status-bar";
import * as AuthSession from "expo-auth-session";
import * as SecureStore from "expo-secure-store";
import * as WebBrowser from "expo-web-browser";
import { NavigationContainer } from "@react-navigation/native";
import { createNativeStackNavigator } from "@react-navigation/native-stack";
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Pressable,
  SafeAreaView,
  StyleSheet,
  Text,
  TextInput,
  View
} from "react-native";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  RepositoryItem,
  PlanItem,
  createPlan,
  listPlans,
  listRepositories,
  startPlanSession
} from "./src/api";

WebBrowser.maybeCompleteAuthSession();

const API_BASE_URL = process.env.EXPO_PUBLIC_API_BASE_URL || "https://micelio.dev";
const OAUTH_CLIENT_ID = process.env.EXPO_PUBLIC_OAUTH_CLIENT_ID || "";
const TOKEN_STORAGE_KEY = "micelio_mobile_access_token";

const discovery = {
  authorizationEndpoint: `${API_BASE_URL}/oauth/authorize`,
  tokenEndpoint: `${API_BASE_URL}/oauth/token`
};

const redirectUri = AuthSession.makeRedirectUri({
  scheme: "micelio"
});

type RootStackParamList = {
  Repositories: { token: string };
  Plans: {
    token: string;
    repository: RepositoryItem;
  };
};

const Stack = createNativeStackNavigator<RootStackParamList>();

function LoginScreen({ onAuthenticated }: { onAuthenticated: (token: string) => void }) {
  const [isExchanging, setIsExchanging] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const [request, response, promptAsync] = AuthSession.useAuthRequest(
    {
      clientId: OAUTH_CLIENT_ID,
      redirectUri,
      responseType: AuthSession.ResponseType.Code,
      usePKCE: true,
      scopes: ["repositories:read", "plans:read", "plans:write", "sessions:write"]
    },
    discovery
  );

  useEffect(() => {
    async function handleResponse() {
      if (response?.type !== "success") {
        return;
      }

      const code = response.params?.code;

      if (!code) {
        setErrorMessage("Authorization did not return a code.");
        return;
      }

      setIsExchanging(true);
      setErrorMessage(null);

      try {
        const tokenResponse = await AuthSession.exchangeCodeAsync(
          {
            clientId: OAUTH_CLIENT_ID,
            code,
            redirectUri,
            extraParams: {
              code_verifier: request?.codeVerifier || ""
            }
          },
          discovery
        );

        if (!tokenResponse.accessToken) {
          throw new Error("Token response did not include an access token.");
        }

        await SecureStore.setItemAsync(TOKEN_STORAGE_KEY, tokenResponse.accessToken);
        onAuthenticated(tokenResponse.accessToken);
      } catch (error) {
        setErrorMessage(error instanceof Error ? error.message : "Authentication failed.");
      } finally {
        setIsExchanging(false);
      }
    }

    handleResponse();
  }, [onAuthenticated, request?.codeVerifier, response]);

  const loginDisabled = !request || isExchanging || OAUTH_CLIENT_ID.trim() === "";

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.loginCard}>
        <Text style={styles.title}>Micelio Mobile</Text>
        <Text style={styles.subtitle}>Browse repositories, prompt requests, and start coding sessions.</Text>

        <Pressable
          style={[styles.button, loginDisabled && styles.buttonDisabled]}
          disabled={loginDisabled}
          onPress={() => promptAsync({ useProxy: false, showInRecents: true })}
        >
          <Text style={styles.buttonText}>{isExchanging ? "Signing in..." : "Sign in"}</Text>
        </Pressable>

        {OAUTH_CLIENT_ID.trim() === "" ? (
          <Text style={styles.warning}>Set EXPO_PUBLIC_OAUTH_CLIENT_ID to your first-party OAuth client id.</Text>
        ) : null}

        {errorMessage ? <Text style={styles.error}>{errorMessage}</Text> : null}
      </View>
      <StatusBar style="auto" />
    </SafeAreaView>
  );
}

function RepositoriesScreen({
  token,
  navigateToPlans,
  onLogout
}: {
  token: string;
  navigateToPlans: (repository: RepositoryItem) => void;
  onLogout: () => void;
}) {
  const [repositories, setRepositories] = useState<RepositoryItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const result = await listRepositories(token);
      setRepositories(result);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : "Failed to load repositories.");
    } finally {
      setLoading(false);
    }
  }, [token]);

  useEffect(() => {
    load();
  }, [load]);

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.screenHeader}>
        <Text style={styles.title}>Repositories</Text>
        <Pressable style={styles.secondaryButton} onPress={onLogout}>
          <Text style={styles.secondaryButtonText}>Log out</Text>
        </Pressable>
      </View>

      {loading ? (
        <View style={styles.centered}>
          <ActivityIndicator />
        </View>
      ) : null}

      {error ? (
        <View style={styles.centered}>
          <Text style={styles.error}>{error}</Text>
          <Pressable style={styles.button} onPress={load}>
            <Text style={styles.buttonText}>Retry</Text>
          </Pressable>
        </View>
      ) : null}

      {!loading && !error ? (
        <FlatList
          data={repositories}
          keyExtractor={(item) => item.id}
          contentContainerStyle={styles.listContent}
          refreshing={loading}
          onRefresh={load}
          renderItem={({ item }) => (
            <Pressable style={styles.card} onPress={() => navigateToPlans(item)}>
              <Text style={styles.cardTitle}>{item.name}</Text>
              <Text style={styles.cardMeta}>
                {item.organization.handle}/{item.handle}
              </Text>
              {item.description ? <Text style={styles.cardBody}>{item.description}</Text> : null}
            </Pressable>
          )}
        />
      ) : null}
    </SafeAreaView>
  );
}

function PlansScreen({ token, repository }: { token: string; repository: RepositoryItem }) {
  const [plans, setPlans] = useState<PlanItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [creating, setCreating] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const result = await listPlans(token, repository.organization.handle, repository.handle);
      setPlans(result);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : "Failed to load plans.");
    } finally {
      setLoading(false);
    }
  }, [repository.handle, repository.organization.handle, token]);

  useEffect(() => {
    load();
  }, [load]);

  const onCreatePlan = useCallback(async () => {
    const trimmedTitle = title.trim();

    if (trimmedTitle === "") {
      Alert.alert("Title required", "Provide a title for the prompt request.");
      return;
    }

    setCreating(true);

    try {
      const plan = await createPlan(
        token,
        repository.organization.handle,
        repository.handle,
        trimmedTitle,
        description.trim()
      );

      setPlans((previous) => [plan, ...previous]);
      setTitle("");
      setDescription("");
    } catch (createError) {
      Alert.alert(
        "Unable to create prompt request",
        createError instanceof Error ? createError.message : "Please try again."
      );
    } finally {
      setCreating(false);
    }
  }, [description, repository.handle, repository.organization.handle, title, token]);

  const onStartSession = useCallback(
    async (plan: PlanItem) => {
      try {
        const updated = await startPlanSession(
          token,
          repository.organization.handle,
          repository.handle,
          plan.number
        );

        setPlans((previous) =>
          previous.map((item) => (item.id === updated.id ? { ...item, ...updated } : item))
        );

        const prUrl = updated.forge_pr_url;
        const previewUrl = updated.sandbox_preview_url;
        const dashboardUrl = updated.sandbox_dashboard_url;

        const details = [previewUrl && `Preview: ${previewUrl}`, prUrl && `Draft PR: ${prUrl}`, dashboardUrl && `Sandbox: ${dashboardUrl}`]
          .filter(Boolean)
          .join("\n");

        Alert.alert(
          "Session started",
          details !== "" ? details : "The coding session started successfully."
        );
      } catch (startError) {
        Alert.alert(
          "Unable to start session",
          startError instanceof Error ? startError.message : "Please try again."
        );
      }
    },
    [repository.handle, repository.organization.handle, token]
  );

  return (
    <SafeAreaView style={styles.container}>
      <Text style={styles.title}>{repository.name}</Text>
      <Text style={styles.subtitle}>Prompt requests</Text>

      <View style={styles.formCard}>
        <TextInput
          value={title}
          onChangeText={setTitle}
          placeholder="Title"
          style={styles.input}
        />
        <TextInput
          value={description}
          onChangeText={setDescription}
          placeholder="Description"
          multiline
          numberOfLines={3}
          style={[styles.input, styles.textArea]}
        />
        <Pressable
          style={[styles.button, creating && styles.buttonDisabled]}
          onPress={onCreatePlan}
          disabled={creating}
        >
          <Text style={styles.buttonText}>{creating ? "Creating..." : "Create prompt request"}</Text>
        </Pressable>
      </View>

      {loading ? (
        <View style={styles.centered}>
          <ActivityIndicator />
        </View>
      ) : null}

      {error ? (
        <View style={styles.centered}>
          <Text style={styles.error}>{error}</Text>
          <Pressable style={styles.button} onPress={load}>
            <Text style={styles.buttonText}>Retry</Text>
          </Pressable>
        </View>
      ) : null}

      {!loading && !error ? (
        <FlatList
          data={plans}
          keyExtractor={(item) => item.id}
          onRefresh={load}
          refreshing={loading}
          contentContainerStyle={styles.listContent}
          renderItem={({ item }) => (
            <View style={styles.card}>
              <Text style={styles.cardTitle}>#{item.number} {item.title}</Text>
              {item.description ? <Text style={styles.cardBody}>{item.description}</Text> : null}
              {item.forge_pr_url ? (
                <Text style={styles.cardMeta}>Draft PR: {item.forge_pr_url}</Text>
              ) : null}
              {item.sandbox_preview_url ? (
                <Text style={styles.cardMeta}>Preview: {item.sandbox_preview_url}</Text>
              ) : null}
              <Pressable style={styles.button} onPress={() => onStartSession(item)}>
                <Text style={styles.buttonText}>Start coding session</Text>
              </Pressable>
            </View>
          )}
        />
      ) : null}
    </SafeAreaView>
  );
}

export default function App() {
  const [token, setToken] = useState<string | null>(null);
  const [loadingToken, setLoadingToken] = useState(true);

  useEffect(() => {
    async function loadStoredToken() {
      try {
        const stored = await SecureStore.getItemAsync(TOKEN_STORAGE_KEY);
        setToken(stored);
      } finally {
        setLoadingToken(false);
      }
    }

    loadStoredToken();
  }, []);

  const handleLogout = useCallback(async () => {
    await SecureStore.deleteItemAsync(TOKEN_STORAGE_KEY);
    setToken(null);
  }, []);

  const repositoriesScreen = useMemo(() => {
    if (!token) {
      return null;
    }

    return (
      <Stack.Screen name="Repositories">
        {(props) => (
          <RepositoriesScreen
            token={token}
            onLogout={handleLogout}
            navigateToPlans={(repository) => props.navigation.navigate("Plans", { token, repository })}
          />
        )}
      </Stack.Screen>
    );
  }, [handleLogout, token]);

  if (loadingToken) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.centered}>
          <ActivityIndicator />
        </View>
      </SafeAreaView>
    );
  }

  if (!token) {
    return <LoginScreen onAuthenticated={setToken} />;
  }

  return (
    <NavigationContainer>
      <Stack.Navigator>
        {repositoriesScreen}
        <Stack.Screen
          name="Plans"
          options={({ route }) => ({
            title: `${route.params.repository.organization.handle}/${route.params.repository.handle}`
          })}
        >
          {({ route }) => (
            <PlansScreen token={route.params.token} repository={route.params.repository} />
          )}
        </Stack.Screen>
      </Stack.Navigator>
      <StatusBar style="auto" />
    </NavigationContainer>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#fff",
    paddingHorizontal: 16,
    paddingTop: 16
  },
  centered: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    gap: 12
  },
  title: {
    fontSize: 24,
    fontWeight: "700",
    color: "#111827"
  },
  subtitle: {
    fontSize: 14,
    color: "#4b5563",
    marginTop: 4,
    marginBottom: 12
  },
  loginCard: {
    marginTop: 80,
    borderWidth: 1,
    borderColor: "#d1d5db",
    borderRadius: 12,
    padding: 16,
    gap: 12
  },
  warning: {
    color: "#92400e",
    fontSize: 13
  },
  error: {
    color: "#b91c1c",
    fontSize: 13,
    textAlign: "center"
  },
  button: {
    borderRadius: 8,
    backgroundColor: "#111827",
    paddingVertical: 10,
    paddingHorizontal: 14,
    alignItems: "center"
  },
  buttonDisabled: {
    opacity: 0.55
  },
  buttonText: {
    color: "#fff",
    fontWeight: "600"
  },
  secondaryButton: {
    borderRadius: 8,
    borderWidth: 1,
    borderColor: "#d1d5db",
    paddingHorizontal: 12,
    paddingVertical: 6
  },
  secondaryButtonText: {
    color: "#111827",
    fontWeight: "500"
  },
  screenHeader: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    marginBottom: 12
  },
  listContent: {
    paddingBottom: 24,
    gap: 10
  },
  card: {
    borderWidth: 1,
    borderColor: "#e5e7eb",
    borderRadius: 10,
    padding: 12,
    gap: 8
  },
  cardTitle: {
    fontSize: 16,
    fontWeight: "600",
    color: "#111827"
  },
  cardMeta: {
    fontSize: 12,
    color: "#4b5563"
  },
  cardBody: {
    fontSize: 14,
    color: "#1f2937"
  },
  formCard: {
    borderWidth: 1,
    borderColor: "#e5e7eb",
    borderRadius: 10,
    padding: 12,
    gap: 10,
    marginBottom: 12
  },
  input: {
    borderWidth: 1,
    borderColor: "#d1d5db",
    borderRadius: 8,
    paddingHorizontal: 10,
    paddingVertical: 8,
    fontSize: 14
  },
  textArea: {
    minHeight: 80,
    textAlignVertical: "top"
  }
});
